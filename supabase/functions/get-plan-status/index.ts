import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";
import { createClient } from "npm:@supabase/supabase-js@^2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

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
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Service unavailable" }, 503);

  const payload = await req.json().catch(() => ({}));
  const outletId = typeof payload.outlet_id === "string" ? payload.outlet_id.trim() : "";
  if (!outletId || outletId.length > 120) {
    return json({ error: "Outlet tidak valid" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const auth = await requireAuthenticatedEmail(supabase, req);
  if ("response" in auth) return auth.response;
  const ownerEmail = auth.email;

  const { data: outlet, error } = await supabase
    .from("outlets")
    .select("license_key, license_expiry, cloud_expiry, owner_email")
    .eq("id", outletId)
    .maybeSingle();
  if (error) return json({ error: "Gagal memuat status" }, 500);
  if (!outlet) return json({ error: "Outlet tidak ditemukan" }, 404);

  const outletOwnerEmail = String(outlet.owner_email || "").trim().toLowerCase();
  if (!outletOwnerEmail || outletOwnerEmail !== ownerEmail) {
    return json({ error: "Outlet bukan milik akun owner ini" }, 403);
  }

  const { data: ownerOutlets, error: ownerOutletsError } = await supabase
    .from("outlets")
    .select("license_key, license_expiry")
    .eq("owner_email", ownerEmail);
  if (ownerOutletsError) return json({ error: "Gagal memuat lisensi owner" }, 500);

  const now = new Date();
  const cloudExpiry = outlet.cloud_expiry ? new Date(outlet.cloud_expiry) : null;
  const isPro = (ownerOutlets || []).some((ownedOutlet) =>
    String(ownedOutlet.license_key || "").trim().toUpperCase().startsWith("PRO")
    && (!ownedOutlet.license_expiry || new Date(ownedOutlet.license_expiry) > now)
  );
  const isCloud = Boolean(isPro && cloudExpiry && cloudExpiry > now);
  return json({
    is_pro: isPro,
    is_cloud: isCloud,
    status: isCloud ? "CLOUD" : isPro ? "PRO" : "FREE",
    expires_at: outlet?.cloud_expiry || null,
  });
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
