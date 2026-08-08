export type MidtransEnvironment = "sandbox" | "production";

export type MidtransConfig = {
  environment: MidtransEnvironment;
  serverKey: string;
  snapHost: string;
};

export type MidtransConfigResult =
  | { ok: true; config: MidtransConfig }
  | { ok: false; code: string; message: string };

type MidtransEnvironmentValues = {
  provider?: string | null;
  productionFlag?: string | null;
  serverKey?: string | null;
};

const normalizeEnvironmentValue = (
  rawValue: string | null | undefined,
  variableName: string,
) => {
  let value = String(rawValue || "").trim();
  value = value.replace(
    new RegExp(`^${variableName}\\s*=\\s*`, "i"),
    "",
  ).trim();

  const hasMatchingQuotes = value.length >= 2 &&
    ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'")));
  if (hasMatchingQuotes) value = value.slice(1, -1).trim();
  return value;
};

export const resolveMidtransConfig = (
  values: MidtransEnvironmentValues,
): MidtransConfigResult => {
  const provider = normalizeEnvironmentValue(
    values.provider,
    "PAYMENT_PROVIDER",
  ).toUpperCase();
  if (provider !== "MIDTRANS") {
    return {
      ok: false,
      code: "MIDTRANS_PROVIDER_INVALID",
      message: "Provider pembayaran belum disetel ke MIDTRANS.",
    };
  }

  const productionFlag = normalizeEnvironmentValue(
    values.productionFlag,
    "MIDTRANS_IS_PRODUCTION",
  ).toLowerCase();
  if (productionFlag !== "true" && productionFlag !== "false") {
    return {
      ok: false,
      code: "MIDTRANS_MODE_INVALID",
      message: "Mode Midtrans harus diisi true (Production) atau false (Sandbox).",
    };
  }

  const serverKey = normalizeEnvironmentValue(
    values.serverKey,
    "MIDTRANS_SERVER_KEY",
  );
  if (!serverKey) {
    return {
      ok: false,
      code: "MIDTRANS_SERVER_KEY_MISSING",
      message: "Midtrans Server Key belum diisi.",
    };
  }

  const isProduction = productionFlag === "true";
  const keyMatchesMode = isProduction
    ? serverKey.startsWith("Mid-server-") && !serverKey.startsWith("SB-")
    : serverKey.startsWith("SB-Mid-server-");
  if (!keyMatchesMode) {
    return {
      ok: false,
      code: "MIDTRANS_SERVER_KEY_MODE_MISMATCH",
      message: isProduction
        ? "Server Key tidak cocok dengan mode Production. Salin Production Server Key dari Midtrans Settings > Access Keys."
        : "Server Key tidak cocok dengan mode Sandbox. Salin Sandbox Server Key (bukan Client Key) dari Midtrans Settings > Access Keys.",
    };
  }

  return {
    ok: true,
    config: {
      environment: isProduction ? "production" : "sandbox",
      serverKey,
      snapHost: isProduction
        ? "https://app.midtrans.com"
        : "https://app.sandbox.midtrans.com",
    },
  };
};

export const readMidtransConfig = (): MidtransConfigResult =>
  resolveMidtransConfig({
    provider: Deno.env.get("PAYMENT_PROVIDER"),
    productionFlag: Deno.env.get("MIDTRANS_IS_PRODUCTION"),
    serverKey: Deno.env.get("MIDTRANS_SERVER_KEY"),
  });
