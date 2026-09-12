import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@^2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Cache-Control": "no-store",
      "Content-Type": "application/json",
    },
  });

const requireAuthenticatedEmail = async (
  supabase: ReturnType<typeof createClient>,
  req: Request,
) => {
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return { response: json({ error: "Login owner dibutuhkan" }, 401) };

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
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Service unavailable" }, 503);

  const payload = await req.json().catch(() => ({}));
  const orderReference = typeof payload.order_reference === "string"
    ? payload.order_reference.trim()
    : "";
  if (!orderReference || orderReference.length > 160) {
    return json({ error: "Referensi pesanan tidak valid" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const auth = await requireAuthenticatedEmail(supabase, req);
  if ("response" in auth) return auth.response;

  const { data: order, error: orderError } = await supabase
    .from("plan_orders")
    .select("outlet_id, plan_code, status, amount, currency, provider_order_id, paid_at, expires_at")
    .eq("payment_provider", "MIDTRANS")
    .eq("provider_order_id", orderReference)
    .maybeSingle();
  if (orderError) return json({ error: "Gagal memuat status pembayaran" }, 500);
  if (!order) return json({ error: "Pesanan tidak ditemukan" }, 404);

  const { data: outlet, error: outletError } = await supabase
    .from("outlets")
    .select("owner_email")
    .eq("id", order.outlet_id)
    .maybeSingle();
  if (outletError) return json({ error: "Gagal memverifikasi pemilik pesanan" }, 500);
  const outletOwnerEmail = String(outlet?.owner_email || "").trim().toLowerCase();
  if (!outletOwnerEmail || outletOwnerEmail !== auth.email) {
    // Do not disclose whether a reference belongs to another account.
    return json({ error: "Pesanan tidak ditemukan" }, 404);
  }

  return json({
    order_reference: order.provider_order_id,
    status: order.status,
    plan_code: order.plan_code,
    amount: Number(order.amount),
    currency: order.currency || "IDR",
    paid_at: order.paid_at || null,
    expires_at: order.expires_at || null,
  });
};

Deno.serve(handler);
