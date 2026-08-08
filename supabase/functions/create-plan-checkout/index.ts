import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@^2";
import {
  checkoutIntegrityHash,
  verifyPlayIntegrity,
} from "./play_integrity.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const errorMessage = (error: unknown) =>
  error instanceof Error ? error.message : String(error);

const plans = {
  PRO_LIFETIME: {
    envKey: "SAJIA_PRO_LIFETIME_PRICE",
    defaultPrice: 149000,
    description: "Sajia Pro - lisensi aplikasi penuh",
  },
  CLOUD_MONTHLY: {
    envKey: "SAJIA_CLOUD_MONTHLY_PRICE",
    defaultPrice: 10000,
    description: "Sajia Cloud - 1 outlet / 1 bulan",
  },
} as const;

type MidtransConfig = {
  environment: "sandbox" | "production";
  serverKey: string;
  snapHost: string;
};

const getMidtransConfig = (): MidtransConfig | null => {
  if (String(Deno.env.get("PAYMENT_PROVIDER") || "").trim().toUpperCase() !== "MIDTRANS") {
    return null;
  }
  const productionFlag = String(Deno.env.get("MIDTRANS_IS_PRODUCTION") || "")
    .trim()
    .toLowerCase();
  if (productionFlag !== "true" && productionFlag !== "false") return null;

  const serverKey = String(Deno.env.get("MIDTRANS_SERVER_KEY") || "").trim();
  const isProduction = productionFlag === "true";
  const keyMatchesMode = isProduction
    ? serverKey.startsWith("Mid-server-") && !serverKey.startsWith("SB-")
    : serverKey.startsWith("SB-Mid-server-");
  if (!keyMatchesMode) return null;

  return {
    environment: isProduction ? "production" : "sandbox",
    serverKey,
    snapHost: isProduction ? "https://app.midtrans.com" : "https://app.sandbox.midtrans.com",
  };
};

const planAlias = (planCode: string) => planCode === "CLOUD_MONTHLY" ? "CLD" : "PRO";

const createProviderOrderId = (planCode: string) =>
  `SJ-${planAlias(planCode)}-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;

const compactMidtransError = (snap: Record<string, unknown>) => {
  const message =
    snap.status_message ||
    snap.error_messages ||
    snap.validation_messages ||
    snap.message ||
    "Midtrans menolak request pembayaran";
  if (Array.isArray(message)) return message.join(", ");
  return String(message);
};

const sha256Hex = async (text: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const markCheckoutFailed = async (
  supabase: ReturnType<typeof createClient>,
  orderId: string,
  reason: string,
) => {
  const { error } = await supabase.from("plan_orders").update({
    status: "FAILED",
    failure_reason: reason.slice(0, 500),
    updated_at: new Date().toISOString(),
  }).eq("id", orderId).eq("status", "PENDING");
  if (error) console.error("Unable to mark failed Midtrans checkout", error.message);
};

const requireAuthenticatedEmail = async (
  supabase: ReturnType<typeof createClient>,
  req: Request,
) => {
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return { response: json({ error: "Login owner dibutuhkan" }, 401) };
  }

  const { data, error } = await supabase.auth.getUser(token);
  const email = data.user?.email?.trim().toLowerCase();
  if (error || !data.user || !email) {
    return { response: json({ error: "Sesi owner tidak valid" }, 401) };
  }

  return { email };
};

const handler = async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Payment service is not configured" }, 503);
  }

  const payload = await req.json().catch(() => ({}));
  const outletId = typeof payload.outlet_id === "string" ? payload.outlet_id.trim() : "";
  const outletName = typeof payload.outlet_name === "string" && payload.outlet_name.trim()
    ? payload.outlet_name.trim()
    : "Outlet Sajia";
  const planCode = typeof payload.plan_code === "string" ? payload.plan_code : "";
  const plan = plans[planCode as keyof typeof plans];
  if (!outletId || outletId.length > 120 || !plan) {
    return json({ error: "Paket atau outlet tidak valid" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const auth = await requireAuthenticatedEmail(supabase, req);
  if ("response" in auth) return auth.response;
  const ownerEmail = auth.email;

  const expectedIntegrityHash = await checkoutIntegrityHash({
    outletId,
    planCode,
  });
  const integrity = await verifyPlayIntegrity({
    integrityToken: typeof payload.integrity_token === "string"
      ? payload.integrity_token
      : undefined,
    providedRequestHash: typeof payload.integrity_request_hash === "string"
      ? payload.integrity_request_hash
      : undefined,
    expectedRequestHash: expectedIntegrityHash,
    enforceEnv: "PLAY_INTEGRITY_ENFORCE_PAYMENT",
  }).catch((error) => ({
    ok: false,
    enforced: true,
    error: `Verifikasi Play Integrity gagal: ${errorMessage(error)}`,
  }));
  if (!integrity.ok) {
    return json({ error: integrity.error || "Aplikasi tidak lolos verifikasi" }, 403);
  }

  const amount = Number(Deno.env.get(plan.envKey) || plan.defaultPrice);
  if (!Number.isInteger(amount) || amount < 1000) {
    return json({ error: "Harga paket belum dikonfigurasi" }, 503);
  }

  const midtrans = getMidtransConfig();
  if (!midtrans) {
    return json({
      error: "Konfigurasi Midtrans tidak konsisten. Periksa provider, mode, dan Server Key.",
    }, 503);
  }

  const { data: outlet, error: outletError } = await supabase
    .from("outlets")
    .select("id, name, owner_email, license_key")
    .eq("id", outletId)
    .maybeSingle();
  if (outletError) return json({ error: "Gagal memuat outlet" }, 500);
  if (!outlet) {
    return json({
      error: "Outlet belum terdaftar di akun. Sinkronkan atau buat cabang terlebih dahulu.",
    }, 404);
  }
  const outletOwnerEmail = String(outlet.owner_email || "").trim().toLowerCase();
  if (!outletOwnerEmail || outletOwnerEmail !== ownerEmail) {
    return json({ error: "Outlet bukan milik akun owner ini" }, 403);
  }

  const { data: ownerOutlets, error: ownerOutletsError } = await supabase
    .from("outlets")
    .select("id, license_key, license_expiry")
    .eq("owner_email", ownerEmail);
  if (ownerOutletsError) return json({ error: "Gagal memeriksa lisensi Pro" }, 500);
  const now = new Date();
  const ownerHasPro = (ownerOutlets || []).some((ownedOutlet) =>
    String(ownedOutlet.license_key || "").trim().toUpperCase().startsWith("PRO")
    && (!ownedOutlet.license_expiry || new Date(ownedOutlet.license_expiry) > now)
  );
  if (planCode === "PRO_LIFETIME" && ownerHasPro) {
    return json({ error: "Sajia Pro sudah aktif untuk akun owner ini" }, 409);
  }
  if (planCode === "CLOUD_MONTHLY" && !ownerHasPro) {
    return json({ error: "Sajia Cloud membutuhkan lisensi Pro" }, 403);
  }

  const successUrl =
    Deno.env.get("SAJIA_PAYMENT_SUCCESS_URL") || "https://sajia-owner.pages.dev/payment/success";
  const failureUrl =
    Deno.env.get("SAJIA_PAYMENT_FAILURE_URL") || "https://sajia-owner.pages.dev/payment/failed";
  const recentSince = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const ownerOutletIds = (ownerOutlets || []).map((ownedOutlet) => String(ownedOutlet.id));
  let pendingQuery = supabase
    .from("plan_orders")
    .select("checkout_url, amount, currency, created_at")
    .eq("plan_code", planCode)
    .eq("payment_provider", "MIDTRANS")
    .eq("provider_environment", midtrans.environment)
    .eq("status", "PENDING")
    .gte("created_at", recentSince);
  pendingQuery = planCode === "PRO_LIFETIME"
    ? pendingQuery.in("outlet_id", ownerOutletIds)
    : pendingQuery.eq("outlet_id", outletId);
  const { data: recentPending, error: recentError } = await pendingQuery
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (recentError) return json({ error: "Gagal memeriksa transaksi aktif" }, 500);
  if (recentPending?.checkout_url) {
    return json({
      checkout_url: recentPending.checkout_url,
      success_url: successUrl,
      amount: Number(recentPending.amount),
      currency: recentPending.currency || "IDR",
      provider: "MIDTRANS",
      reused: true,
    });
  }
  if (recentPending) {
    return json({ error: "Pembayaran sedang dibuat. Tunggu sebentar lalu coba lagi." }, 409);
  }

  const rateSince = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  let rateQuery = supabase
    .from("plan_orders")
    .select("id", { count: "exact", head: true })
    .eq("payment_provider", "MIDTRANS")
    .gte("created_at", rateSince);
  rateQuery = planCode === "PRO_LIFETIME"
    ? rateQuery.in("outlet_id", ownerOutletIds)
    : rateQuery.eq("outlet_id", outletId);
  const { count: recentCount, error: rateError } = await rateQuery;
  if (rateError) return json({ error: "Gagal memeriksa batas pembayaran" }, 500);
  if ((recentCount || 0) >= 4) {
    return json({ error: "Terlalu banyak percobaan pembayaran. Coba lagi dalam 10 menit." }, 429);
  }

  const externalId = createProviderOrderId(planCode);
  const requestedIdempotencyKey = String(req.headers.get("idempotency-key") || "")
    .trim()
    .slice(0, 128);
  const timeBucket = Math.floor(Date.now() / (5 * 60 * 1000));
  const entitlementScope = planCode === "PRO_LIFETIME" ? ownerEmail : outletId;
  const checkoutFingerprint = await sha256Hex(
    `${ownerEmail}|${entitlementScope}|${planCode}|${midtrans.environment}|${requestedIdempotencyKey || timeBucket}`,
  );
  const pendingInsert = await supabase.from("plan_orders").insert({
    outlet_id: outletId,
    plan_code: planCode,
    status: "PENDING",
    amount,
    currency: "IDR",
    payment_provider: "MIDTRANS",
    provider_environment: midtrans.environment,
    provider_order_id: externalId,
    xendit_external_id: externalId,
    checkout_fingerprint: checkoutFingerprint,
  }).select("id").single();
  if (pendingInsert.error || !pendingInsert.data) {
    if (pendingInsert.error?.code === "23505") {
      return json({ error: "Pembayaran yang sama sedang diproses." }, 409);
    }
    return json({ error: "Gagal menyiapkan transaksi pembayaran" }, 500);
  }
  const paymentOrderId = String(pendingInsert.data.id);

  let midtransResponse: Response;
  try {
    midtransResponse = await fetch(`${midtrans.snapHost}/snap/v1/transactions`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${midtrans.serverKey}:`)}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        // Keep each transaction self-contained. This also prevents sandbox and
        // production dashboard notification settings from drifting apart.
        "X-Override-Notification": `${supabaseUrl}/functions/v1/midtrans-webhook`,
      },
      body: JSON.stringify({
        transaction_details: {
          order_id: externalId,
          gross_amount: amount,
        },
        item_details: [{
          id: planCode,
          name: plan.description,
          price: amount,
          quantity: 1,
        }],
        customer_details: {
          first_name: outlet.name || outletName,
          email: outletOwnerEmail,
        },
        callbacks: {
          finish: successUrl,
          error: failureUrl,
          pending: successUrl,
        },
      }),
    });
  } catch (error) {
    await markCheckoutFailed(supabase, paymentOrderId, `MIDTRANS_NETWORK: ${errorMessage(error)}`);
    return json({ error: "Midtrans tidak dapat dihubungi. Coba lagi beberapa saat." }, 502);
  }

  const snap = await midtransResponse.json().catch(() => ({}));
  if (!midtransResponse.ok || !snap.redirect_url || !snap.token) {
    await markCheckoutFailed(
      supabase,
      paymentOrderId,
      `MIDTRANS_${midtransResponse.status}: ${compactMidtransError(snap)}`,
    );
    return json({
      error: `Gagal membuat halaman pembayaran Midtrans: ${compactMidtransError(snap)}`,
      midtrans_status: midtransResponse.status,
    }, 502);
  }

  const checkoutUpdate = await supabase.from("plan_orders").update({
    provider_reference_id: snap.token,
    checkout_url: snap.redirect_url,
    updated_at: new Date().toISOString(),
  }).eq("id", paymentOrderId).eq("status", "PENDING");
  if (checkoutUpdate.error) {
    // The order was persisted before calling Midtrans, so its signed webhook can
    // still provision the plan. Return the live URL to avoid charging twice.
    console.error("Unable to persist Midtrans redirect URL", checkoutUpdate.error.message);
  }

  return json({
    checkout_url: snap.redirect_url,
    success_url: successUrl,
    amount,
    currency: "IDR",
    provider: "MIDTRANS",
  });
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
