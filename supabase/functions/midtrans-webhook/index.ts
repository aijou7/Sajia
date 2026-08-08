import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@^2";
import { readMidtransConfig } from "./midtrans_config.ts";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const sha512 = async (text: string) => {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-512", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const constantTimeEqual = (left: string, right: string) => {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
};

const validTimestamp = (value: unknown) => {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
};

const handler = async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const midtransResult = readMidtransConfig();
  if (!supabaseUrl || !serviceRoleKey || !midtransResult.ok) {
    if (!midtransResult.ok) {
      console.error("Midtrans configuration error", midtransResult.code);
    }
    return json({ error: "Service unavailable" }, 503);
  }
  const midtrans = midtransResult.config;

  const event = await req.json().catch(() => null);
  const orderId = typeof event?.order_id === "string" ? event.order_id.trim() : "";
  const statusCode = typeof event?.status_code === "string"
    ? event.status_code.trim()
    : String(event?.status_code || "").trim();
  const grossAmountText = typeof event?.gross_amount === "string"
    ? event.gross_amount.trim()
    : String(event?.gross_amount || "").trim();
  const transactionStatus = typeof event?.transaction_status === "string"
    ? event.transaction_status.trim().toLowerCase()
    : "";
  const signature = typeof event?.signature_key === "string"
    ? event.signature_key.trim().toLowerCase()
    : "";
  if (
    !orderId || orderId.length > 160 || !statusCode || !grossAmountText ||
    !transactionStatus || !/^[a-f0-9]{128}$/.test(signature)
  ) {
    return json({ error: "Invalid Midtrans event" }, 400);
  }

  const expectedSignature = await sha512(
    `${orderId}${statusCode}${grossAmountText}${midtrans.serverKey}`,
  );
  if (!constantTimeEqual(signature, expectedSignature)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const grossAmount = Number(grossAmountText);
  if (!Number.isFinite(grossAmount) || grossAmount <= 0) {
    return json({ error: "Invalid payment amount" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await supabase.rpc("process_midtrans_notification", {
    p_order_id: orderId,
    p_transaction_status: transactionStatus,
    p_fraud_status: typeof event.fraud_status === "string"
      ? event.fraud_status.trim().toLowerCase()
      : "",
    p_gross_amount: grossAmount,
    p_paid_at: validTimestamp(event.settlement_time) ||
      validTimestamp(event.transaction_time) || new Date().toISOString(),
    p_reference_id: typeof event.transaction_id === "string"
      ? event.transaction_id.trim().slice(0, 200)
      : null,
    p_environment: midtrans.environment,
  });
  if (error) {
    const message = String(error.message || "");
    if (message.includes("PAYMENT_AMOUNT_MISMATCH")) {
      return json({ error: "Jumlah pembayaran tidak cocok" }, 400);
    }
    if (message.includes("PAYMENT_ENVIRONMENT_MISMATCH")) {
      return json({ error: "Lingkungan pembayaran tidak cocok" }, 400);
    }
    console.error("Atomic Midtrans provisioning failed", error);
    // A non-2xx response asks Midtrans to retry. No entitlement can be partially
    // provisioned because the RPC runs in one PostgreSQL transaction.
    return json({ error: "Gagal memproses notifikasi pembayaran" }, 500);
  }

  return json({ received: true, result: data });
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
