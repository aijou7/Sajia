import {
  canonicalJson,
  sha256Hex,
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const payload = await req.json().catch(() => ({}));
  const action = typeof payload.action === "string" ? payload.action : "";
  const requestPayload = payload.payload &&
      typeof payload.payload === "object" &&
      !Array.isArray(payload.payload)
    ? payload.payload as Record<string, unknown>
    : {};

  if (!action) return json({ error: "Action tidak valid" }, 400);

  const expectedRequestHash = await sha256Hex(
    canonicalJson({ action, ...requestPayload }),
  );
  const integrity = await verifyPlayIntegrity({
    integrityToken: typeof payload.integrity_token === "string"
      ? payload.integrity_token
      : undefined,
    providedRequestHash: typeof payload.integrity_request_hash === "string"
      ? payload.integrity_request_hash
      : undefined,
    expectedRequestHash,
  }).catch((error) => ({
    ok: false,
    enforced: true,
    error: `Verifikasi Play Integrity gagal: ${errorMessage(error)}`,
  }));

  if (!integrity.ok) {
    return json({ ok: false, error: integrity.error }, 403);
  }

  return json({
    ok: true,
    enforced: integrity.enforced,
  });
});
