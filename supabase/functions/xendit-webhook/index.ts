import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const addOneMonth = (date: Date) => {
  const result = new Date(date);
  result.setMonth(result.getMonth() + 1);
  return result;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const callbackToken = req.headers.get("x-callback-token");
  const expectedToken = Deno.env.get("XENDIT_WEBHOOK_TOKEN");
  if (!expectedToken || callbackToken !== expectedToken) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Service unavailable" }, 503);

  const event = await req.json().catch(() => null);
  if (!event?.id || !event?.external_id || !event?.status) {
    return json({ error: "Invalid Xendit event" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data: order, error } = await supabase
    .from("plan_orders")
    .select("id, outlet_id, plan_code, amount, status")
    .eq("xendit_invoice_id", event.id)
    .eq("xendit_external_id", event.external_id)
    .maybeSingle();
  if (error) return json({ error: "Gagal memuat transaksi" }, 500);
  if (!order) return json({ received: true });

  const status = String(event.status).toUpperCase();
  if (status === "PAID" || status === "SETTLED") {
    if (Number(event.amount) !== Number(order.amount)) {
      return json({ error: "Jumlah pembayaran tidak cocok" }, 400);
    }

    const paidAt = event.paid_at ? new Date(event.paid_at) : new Date();
    await supabase.from("plan_orders").update({
      status: "ACTIVE",
      paid_at: paidAt.toISOString(),
      starts_at: paidAt.toISOString(),
    }).eq("id", order.id);

    if (order.plan_code === "PRO_LIFETIME") {
      await supabase.from("outlets").update({
        license_key: "PRO",
        license_expiry: null,
      }).eq("id", order.outlet_id);
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

      await supabase.from("plan_orders").update({
        expires_at: cloudExpiry.toISOString(),
      }).eq("id", order.id);
      await supabase.from("outlets").update({
        cloud_expiry: cloudExpiry.toISOString(),
      }).eq("id", order.outlet_id);
    }
  } else if (["EXPIRED", "FAILED"].includes(status)) {
    await supabase.from("plan_orders").update({ status }).eq("id", order.id);
  }

  return json({ received: true });
});
