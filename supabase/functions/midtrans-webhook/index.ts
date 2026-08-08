import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@^2";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const addOneMonth = (date: Date) => {
  const result = new Date(date);
  result.setMonth(result.getMonth() + 1);
  return result;
};

const sha512 = async (text: string) => {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-512", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const handler = async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  if (!supabaseUrl || !serviceRoleKey || !serverKey) {
    return json({ error: "Service unavailable" }, 503);
  }

  const event = await req.json().catch(() => null);
  if (!event?.order_id || !event?.status_code || !event?.gross_amount) {
    return json({ error: "Invalid Midtrans event" }, 400);
  }

  const expectedSignature = await sha512(
    `${event.order_id}${event.status_code}${event.gross_amount}${serverKey}`,
  );
  if (event.signature_key !== expectedSignature) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  let { data: order, error } = await supabase
    .from("plan_orders")
    .select("id, outlet_id, plan_code, amount, status")
    .eq("payment_provider", "MIDTRANS")
    .eq("provider_order_id", event.order_id)
    .maybeSingle();
  if (error) return json({ error: "Gagal memuat transaksi" }, 500);
  if (!order) {
    const fallback = await supabase
      .from("plan_orders")
      .select("id, outlet_id, plan_code, amount, status")
      .eq("xendit_external_id", event.order_id)
      .maybeSingle();
    if (fallback.error) return json({ error: "Gagal memuat transaksi" }, 500);
    order = fallback.data;
  }
  if (!order) return json({ received: true });

  const status = String(event.transaction_status || "").toLowerCase();
  const fraudStatus = String(event.fraud_status || "").toLowerCase();
  const paid = status === "settlement" || (status === "capture" && fraudStatus !== "deny");
  const failed = ["expire", "cancel", "deny", "failure"].includes(status);

  if (paid) {
    if (Number(event.gross_amount) !== Number(order.amount)) {
      return json({ error: "Jumlah pembayaran tidak cocok" }, 400);
    }

    const paidAt = event.settlement_time
      ? new Date(event.settlement_time)
      : event.transaction_time
        ? new Date(event.transaction_time)
        : new Date();

    const activateOrder = await supabase.from("plan_orders").update({
      status: "ACTIVE",
      paid_at: paidAt.toISOString(),
      starts_at: paidAt.toISOString(),
      payment_provider: "MIDTRANS",
      provider_order_id: event.order_id,
      provider_reference_id: event.transaction_id || null,
    }).eq("id", order.id);
    if (activateOrder.error) return json({ error: "Gagal mengaktifkan pembayaran" }, 500);

    if (order.plan_code === "PRO_LIFETIME") {
      const { data: paidOutlet, error: paidOutletError } = await supabase
        .from("outlets")
        .select("owner_email")
        .eq("id", order.outlet_id)
        .maybeSingle();
      if (paidOutletError || !paidOutlet) {
        return json({ error: "Outlet pembayaran tidak ditemukan" }, 500);
      }
      const ownerEmail = String(paidOutlet.owner_email || "").trim().toLowerCase();
      if (!ownerEmail) {
        return json({ error: "Email owner pada outlet pembayaran tidak valid" }, 500);
      }
      const activatePro = await supabase.from("outlets").update({
        license_key: "PRO",
        license_expiry: null,
      }).ilike("owner_email", ownerEmail);
      if (activatePro.error) return json({ error: "Gagal mengaktifkan Sajia Pro" }, 500);
    }

    if (order.plan_code === "CLOUD_MONTHLY") {
      const { data: outlet } = await supabase.from("outlets")
        .select("cloud_expiry")
        .eq("id", order.outlet_id)
        .maybeSingle();
      const currentExpiry = outlet?.cloud_expiry
        ? new Date(outlet.cloud_expiry)
        : null;
      const expiryBase = currentExpiry && currentExpiry > paidAt
        ? currentExpiry
        : paidAt;
      const cloudExpiry = addOneMonth(expiryBase);

      const updateExpiry = await supabase.from("plan_orders").update({
        expires_at: cloudExpiry.toISOString(),
      }).eq("id", order.id);
      if (updateExpiry.error) return json({ error: "Gagal menyimpan masa Cloud" }, 500);
      const activateCloud = await supabase.from("outlets").update({
        cloud_expiry: cloudExpiry.toISOString(),
      }).eq("id", order.outlet_id);
      if (activateCloud.error) return json({ error: "Gagal mengaktifkan Sajia Cloud" }, 500);
    }
  } else if (failed) {
    const markFailed = await supabase.from("plan_orders").update({
      status: status === "expire" ? "EXPIRED" : "FAILED",
      payment_provider: "MIDTRANS",
      provider_order_id: event.order_id,
      provider_reference_id: event.transaction_id || null,
    }).eq("id", order.id);
    if (markFailed.error) return json({ error: "Gagal memperbarui transaksi" }, 500);
  }

  return json({ received: true });
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
