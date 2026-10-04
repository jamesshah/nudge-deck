export function apnsConfigured(): boolean {
  return Boolean(
    process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      process.env.APNS_PRIVATE_KEY &&
      process.env.APNS_TOPIC,
  );
}

/**
 * Convex env values often arrive with literal `\n`, lost newlines, or wrapping
 * quotes from a dashboard paste. Rebuild a PKCS#8 PEM OpenSSL can decode.
 */
export function normalizeApnsPrivateKey(raw: string): string {
  let key = raw.trim();
  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1).trim();
  }
  key = key.replace(/\\n/g, "\n").replace(/\r\n?/g, "\n");

  const begin = "-----BEGIN PRIVATE KEY-----";
  const end = "-----END PRIVATE KEY-----";
  const beginAt = key.indexOf(begin);
  const endAt = key.indexOf(end);
  if (beginAt === -1 || endAt === -1 || endAt <= beginAt) {
    throw new Error(
      "APNS_PRIVATE_KEY must be the full .p8 PEM, including BEGIN/END PRIVATE KEY lines.",
    );
  }
  const body = key
    .slice(beginAt + begin.length, endAt)
    .replace(/[^A-Za-z0-9+/=]/g, "");
  if (!body) {
    throw new Error("APNS_PRIVATE_KEY is missing the base64 key body.");
  }
  const lines = body.match(/.{1,64}/g) ?? [body];
  return `${begin}\n${lines.join("\n")}\n${end}\n`;
}
