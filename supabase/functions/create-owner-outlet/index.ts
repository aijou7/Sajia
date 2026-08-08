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

  const { data, error } = await supabase.rpc("create_owner_outlet_secure", {
    p_id: id,
    p_name: name,
    p_address: cleanOptionalText(payload.address, 300),
    p_phone: cleanOptionalText(payload.phone, 40),
    p_owner_email: ownerEmail,
  });
  if (error) {
    const message = String(error.message || "");
    if (message.includes("SAJIA_PRO_REQUIRED_FOR_ADDITIONAL_OUTLET")) {
      return json({ error: "Tambah cabang membutuhkan Sajia Pro" }, 403);
    }
    if (message.includes("OUTLET_ID_ALREADY_EXISTS")) {
      return json({ error: "ID cabang sudah digunakan" }, 409);
    }
    console.error("Secure outlet creation failed", error);
    return json({ error: "Gagal membuat cabang" }, 500);
  }
  if (!data || typeof data !== "object") {
    return json({ error: "Gagal membuat cabang" }, 500);
  }

  const response = data as Record<string, unknown>;
  return json(response, response.created === false ? 200 : 201);
};

export default {
  fetch: withSupabase({ auth: "none" }, handler),
};
