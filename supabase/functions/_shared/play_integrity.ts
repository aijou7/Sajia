export const canonicalJson = (value: Record<string, unknown>) =>
  JSON.stringify(
    Object.fromEntries(
      Object.entries(value).sort(([left], [right]) => left.localeCompare(right)),
    ),
  );

export const sha256Hex = async (value: string) => {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

export const checkoutIntegrityHash = (payload: {
  outletId: string;
  planCode: string;
}) =>
  sha256Hex(
    canonicalJson({
      action: "create_plan_checkout",
      outlet_id: payload.outletId,
      plan_code: payload.planCode,
    }),
  );

type IntegrityResult = {
  ok: boolean;
  enforced: boolean;
  error?: string;
  verdict?: Record<string, unknown>;
};

export const verifyPlayIntegrity = async (payload: {
  integrityToken?: string;
  providedRequestHash?: string;
  expectedRequestHash: string;
  enforceEnv?: string;
}): Promise<IntegrityResult> => {
  const enforced =
    envFlag("PLAY_INTEGRITY_ENFORCE") || envFlag(payload.enforceEnv || "");

  if (!enforced) {
    return { ok: true, enforced: false };
  }

  if (!payload.integrityToken || !payload.providedRequestHash) {
    return {
      ok: false,
      enforced,
      error: "Verifikasi aplikasi dibutuhkan. Update/install Sajia dari sumber resmi.",
    };
  }

  if (payload.providedRequestHash !== payload.expectedRequestHash) {
    return {
      ok: false,
      enforced,
      error: "Request pembayaran tidak lolos verifikasi integritas.",
    };
  }

  const packageName =
    Deno.env.get("PLAY_INTEGRITY_PACKAGE_NAME") || "id.aksaldev.sajia";
  const verdict = await decodeIntegrityToken(packageName, payload.integrityToken);
  if (!verdict.ok) return verdict;

  const tokenPayload = verdict.verdict || {};
  const requestDetails = objectValue(tokenPayload.requestDetails);
  const appIntegrity = objectValue(tokenPayload.appIntegrity);
  const deviceIntegrity = objectValue(tokenPayload.deviceIntegrity);

  const verdictHash = stringValue(requestDetails.requestHash);
  if (verdictHash !== payload.expectedRequestHash) {
    return {
      ok: false,
      enforced,
      error: "Hash request Play Integrity tidak cocok.",
      verdict: tokenPayload,
    };
  }

  const verdictPackage =
    stringValue(appIntegrity.packageName) ||
    stringValue(requestDetails.requestPackageName) ||
    stringValue(requestDetails.packageName);
  if (verdictPackage && verdictPackage !== packageName) {
    return {
      ok: false,
      enforced,
      error: "Package aplikasi tidak cocok dengan Sajia resmi.",
      verdict: tokenPayload,
    };
  }

  const appRecognitionVerdict = stringValue(appIntegrity.appRecognitionVerdict);
  if (appRecognitionVerdict !== "PLAY_RECOGNIZED") {
    return {
      ok: false,
      enforced,
      error: "Aplikasi tidak dikenali sebagai build resmi Google Play.",
      verdict: tokenPayload,
    };
  }

  const requiredCert = Deno.env.get("PLAY_INTEGRITY_CERT_SHA256");
  const certs = arrayValue(appIntegrity.certificateSha256Digest)
    .map((item) => String(item).toLowerCase());
  if (requiredCert && !certs.includes(requiredCert.toLowerCase())) {
    return {
      ok: false,
      enforced,
      error: "Signature aplikasi tidak cocok dengan release resmi.",
      verdict: tokenPayload,
    };
  }

  const allowedDeviceVerdicts = (
    Deno.env.get("PLAY_INTEGRITY_ALLOWED_DEVICE_VERDICTS") ||
    "MEETS_DEVICE_INTEGRITY,MEETS_STRONG_INTEGRITY"
  )
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  const deviceVerdicts = arrayValue(deviceIntegrity.deviceRecognitionVerdict)
    .map((item) => String(item));
  const deviceOk = deviceVerdicts.some((verdict) =>
    allowedDeviceVerdicts.includes(verdict)
  );
  if (!deviceOk) {
    return {
      ok: false,
      enforced,
      error: "Perangkat tidak lolos pemeriksaan integritas.",
      verdict: tokenPayload,
    };
  }

  return { ok: true, enforced, verdict: tokenPayload };
};

const decodeIntegrityToken = async (
  packageName: string,
  integrityToken: string,
): Promise<IntegrityResult> => {
  const accessToken = await getGoogleAccessToken();
  const response = await fetch(
    `https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ integrityToken }),
    },
  );
  const decoded = await response.json().catch(() => ({}));
  if (!response.ok) {
    const errorBody = objectValue(decoded.error);
    return {
      ok: false,
      enforced: true,
      error: `Google Play Integrity gagal: ${
        stringValue(errorBody.message) || response.status
      }`,
    };
  }

  return {
    ok: true,
    enforced: true,
    verdict: objectValue(decoded.tokenPayloadExternal),
  };
};

const getGoogleAccessToken = async () => {
  const serviceAccountJson = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  const parsed = serviceAccountJson ? JSON.parse(serviceAccountJson) : {};
  const clientEmail =
    Deno.env.get("GOOGLE_CLIENT_EMAIL") || stringValue(parsed.client_email);
  const privateKey = (
    Deno.env.get("GOOGLE_PRIVATE_KEY") || stringValue(parsed.private_key)
  ).replaceAll("\\n", "\n");

  if (!clientEmail || !privateKey) {
    throw new Error("Secret Google service account Play Integrity belum diset");
  }

  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/playintegrity",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }, privateKey);

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const token = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || !token.access_token) {
    throw new Error(
      `Gagal mengambil token Google: ${
        stringValue(token.error_description) || tokenResponse.status
      }`,
    );
  }
  return String(token.access_token);
};

const signJwt = async (claims: Record<string, unknown>, privateKeyPem: string) => {
  const header = { alg: "RS256", typ: "JWT" };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;
};

const base64UrlJson = (value: Record<string, unknown>) =>
  base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));

const base64UrlBytes = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");

const pemToArrayBuffer = (pem: string) => {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
};

const envFlag = (name: string) =>
  name.length > 0 &&
  String(Deno.env.get(name) || "false").toLowerCase() === "true";

const objectValue = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

const arrayValue = (value: unknown): unknown[] =>
  Array.isArray(value) ? value : [];

const stringValue = (value: unknown) =>
  typeof value === "string" ? value : "";
