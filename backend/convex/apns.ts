"use node";

import { createPrivateKey, sign } from "node:crypto";
import http2 from "node:http2";
import { v } from "convex/values";
import { normalizeApnsPrivateKey } from "./lib/apnsConfig";
import { internalAction } from "./_generated/server";

const HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

function providerToken(): string {
  const keyId = process.env.APNS_KEY_ID!;
  const teamId = process.env.APNS_TEAM_ID!;
  const pem = normalizeApnsPrivateKey(process.env.APNS_PRIVATE_KEY!);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const signature = sign("sha256", Buffer.from(signingInput), {
    key: createPrivateKey(pem),
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64url(signature)}`;
}

function sendOne(
  session: http2.ClientHttp2Session,
  jwt: string,
  deviceToken: string,
  payload: string,
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = session.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": process.env.APNS_TOPIC!,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    });
    let status = 0;
    let body = "";
    req.setEncoding("utf8");
    req.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    req.on("data", (chunk: string) => {
      body += chunk;
    });
    req.on("end", () => resolve({ status, body }));
    req.on("error", reject);
    req.end(payload);
  });
}

/** Returns the device tokens APNs reported as no longer valid. */
export const send = internalAction({
  args: {
    devices: v.array(
      v.object({
        apnsToken: v.string(),
        environment: v.union(v.literal("sandbox"), v.literal("production")),
      }),
    ),
    title: v.string(),
    body: v.string(),
  },
  returns: v.array(v.string()),
  handler: async (_ctx, args) => {
    const jwt = providerToken();
    const payload = JSON.stringify({
      aps: { alert: { title: args.title, body: args.body }, sound: "default" },
    });
    const invalid: string[] = [];

    for (const environment of ["sandbox", "production"] as const) {
      const devices = args.devices.filter((d) => d.environment === environment);
      if (devices.length === 0) continue;
      const session = http2.connect(HOSTS[environment]);
      try {
        for (const device of devices) {
          try {
            const { status, body } = await sendOne(session, jwt, device.apnsToken, payload);
            if (status === 410 || (status === 400 && body.includes("BadDeviceToken"))) {
              invalid.push(device.apnsToken);
            } else if (status !== 200) {
              console.error(`APNs ${status} for ${environment} device: ${body}`);
            }
          } catch (error) {
            console.error("APNs request failed", error);
          }
        }
      } finally {
        session.close();
      }
    }
    return invalid;
  },
});
