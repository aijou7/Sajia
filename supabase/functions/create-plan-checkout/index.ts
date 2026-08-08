import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@^2";
import {
  checkoutIntegrityHash,
  verifyPlayIntegrity,
} from "../_shared/play_integrity.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

const isProductionMidtrans = () =>
  String(Deno.env.get("MIDTRANS_IS_PRODUCTION") || "false").toLowerCase() === "true";

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

const addPaymentOrder = async (
  supabase: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
) => {
  const { error } = await supabase.from("plan_orders").insert(payload);
  if (error) throw error;
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

  let { data: outlet, error: outletError } = await supabase
    .from("outlets")
    .select("id, name, owner_email, license_key")
    .eq("id", outletId)
    .maybeSingle();
  if (outletError) return json({ error: "Gagal memuat outlet" }, 500);

  if (!outlet) {
    const { count: ownedOutletCount, error: countError } = await supabase
      .from("outlets")
      .select("id", { count: "exact", head: true })
      .ilike("owner_email", ownerEmail);
    if (countError) return json({ error: "Gagal memeriksa outlet owner" }, 500);
    if ((ownedOutletCount || 0) > 0) {
      return json({
        error: "Outlet aktif tidak cocok dengan akun. Sinkronkan data lalu pilih cabang yang terdaftar.",
      }, 409);
    }
    const insert = await supabase.from("outlets").insert({
      id: outletId,
      name: outletName,
      owner_email: ownerEmail,
      license_key: "FREE",
    }).select("id, name, owner_email, license_key").single();
    if (insert.error) return json({ error: "Gagal menyiapkan outlet" }, 500);
    outlet = insert.data;
  } else {
    const outletOwnerEmail = String(outlet.owner_email || "").trim().toLowerCase();
    if (outletOwnerEmail && outletOwnerEmail !== ownerEmail) {
      return json({ error: "Outlet bukan milik akun owner ini" }, 403);
    }
    if (!outletOwnerEmail) {
      await supabase.from("outlets")
        .update({ owner_email: ownerEmail })
        .eq("id", outletId);
      outlet.owner_email = ownerEmail;
    }
  }

  if (planCode === "CLOUD_MONTHLY") {
    const { data: ownerOutlets, error: ownerOutletsError } = await supabase
      .from("outlets")
      .select("license_key")
      .ilike("owner_email", ownerEmail);
    if (ownerOutletsError) return json({ error: "Gagal memeriksa lisensi Pro" }, 500);
    const ownerHasPro = (ownerOutlets || []).some((ownedOutlet) =>
      String(ownedOutlet.license_key || "").trim().toUpperCase().startsWith("PRO")
    );
    if (!ownerHasPro) {
      return json({ error: "Sajia Cloud membutuhkan lisensi Pro" }, 403);
    }
  }

  const successUrl =
    Deno.env.get("SAJIA_PAYMENT_SUCCESS_URL") || "https://sajia-owner.pages.dev/payment/success";
  const failureUrl =
    Deno.env.get("SAJIA_PAYMENT_FAILURE_URL") || "https://sajia-owner.pages.dev/payment/failed";
  const externalId = createProviderOrderId(planCode);

  const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  if (!serverKey) return json({ error: "Midtrans belum dikonfigurasi" }, 503);

  const snapHost = isProductionMidtrans()
    ? "https://app.midtrans.com"
    : "https://app.sandbox.midtrans.com";
  const midtransResponse = await fetch(`${snapHost}/snap/v1/transactions`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${serverKey}:`)}`,
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
        first_name: outlet.name,
        email: outlet.owner_email || undefined,
      },
      callbacks: {
        finish: successUrl,
        error: failureUrl,
        pending: successUrl,
      },
    }),
  });

  const snap = await midtransResponse.json().catch(() => ({}));
  if (!midtransResponse.ok || !snap.redirect_url || !snap.token) {
    return json({
      error: `Gagal membuat halaman pembayaran Midtrans: ${compactMidtransError(snap)}`,
      midtrans_status: midtransResponse.status,
    }, 502);
  }

  await addPaymentOrder(supabase, {
    outlet_id: outletId,
    plan_code: planCode,
    status: "PENDING",
    amount,
    currency: "IDR",
    payment_provider: "MIDTRANS",
    provider_order_id: externalId,
    provider_reference_id: snap.token,
    // Legacy schema column retained for compatibility with older DB migrations.
    xendit_external_id: externalId,
    checkout_url: snap.redirect_url,
  });

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
