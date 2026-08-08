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

const cleanOptionalText = (value: unknown, maxLength: number) => {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned ? cleaned.slice(0, maxLength) : null;
};

const handler = async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Service unavailable" }, 503);

  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  const ownerEmail = authData.user?.email?.trim().toLowerCase();
  if (authError || !authData.user || !ownerEmail) {
    return json({ error: "Sesi owner tidak valid" }, 401);
  }

  const payload = await req.json().catch(() => ({}));
  const id = typeof payload.id === "string" ? payload.id.trim() : "";
  const name = typeof payload.name === "string" ? payload.name.trim() : "";
  if (!/^[0-9a-f-]{36}$/i.test(id) || !name || name.length > 120) {
    return json({ error: "Data cabang tidak valid" }, 400);
  }

  const { data: ownerOutlets, error: ownerOutletsError } = await supabase
    .from("outlets")
    .select("id, license_key")
    .ilike("owner_email", ownerEmail);
  if (ownerOutletsError) return json({ error: "Gagal memeriksa lisensi owner" }, 500);

  const hasPro = (ownerOutlets || []).some((outlet) =>
    String(outlet.license_key || "").trim().toUpperCase().startsWith("PRO")
  );
  if ((ownerOutlets || []).length > 0 && !hasPro) {
    return json({ error: "Tambah cabang membutuhkan Sajia Pro" }, 403);
  }

  const { data: existingOutlet, error: existingError } = await supabase
    .from("outlets")
    .select("id, owner_email")
    .eq("id", id)
    .maybeSingle();
  if (existingError) return json({ error: "Gagal memeriksa cabang" }, 500);
  if (existingOutlet) {
    const existingOwner = String(existingOutlet.owner_email || "").trim().toLowerCase();
    if (existingOwner && existingOwner !== ownerEmail) {
      return json({ error: "ID cabang sudah digunakan" }, 409);
    }
  }

  const { data: outlet, error: upsertError } = await supabase
    .from("outlets")
    .upsert({
      id,
      name,
      address: cleanOptionalText(payload.address, 300),
      phone: cleanOptionalText(payload.phone, 40),
      owner_email: ownerEmail,
      license_key: hasPro ? "PRO" : "FREE",
      license_expiry: null,
      cloud_expiry: null,
    }, { onConflict: "id" })
    .select("id, name, address, phone, cloud_expiry")
    .single();
  if (upsertError || !outlet) return json({ error: "Gagal membuat cabang" }, 500);

  return json({
    outlet,
    is_pro: hasPro,
    is_cloud: false,
  }, 201);
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
