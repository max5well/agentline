import { createPrivateKey, sign } from "node:crypto";
import { connect } from "node:http2";

export type APNsEnvironment = "sandbox" | "production";

export type VoIPPush = {
  callId: string;
  agentId: string;
  agentName: string;
  agentEmoji: string;
  brief: string;
  deadline?: string;
};

export type APNsResult = {
  ok: boolean;
  status: number;
  reason?: string;
};

let cachedProviderToken: { value: string; createdAt: number } | null = null;

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

function providerToken(): string {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const rawKey = process.env.APNS_PRIVATE_KEY;
  if (!keyId || !teamId || !rawKey) {
    throw new Error("APNs credentials are not configured");
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.createdAt < 50 * 60) {
    return cachedProviderToken.value;
  }

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;
  const key = createPrivateKey(rawKey.replace(/\\n/g, "\n"));
  // JWS uses the fixed-width IEEE-P1363 R||S representation, not ASN.1 DER.
  const signature = sign("sha256", Buffer.from(signingInput), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  const value = `${signingInput}.${base64url(signature)}`;
  cachedProviderToken = { value, createdAt: now };
  return value;
}

export function apnsConfigured(): boolean {
  return Boolean(
    process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      process.env.APNS_PRIVATE_KEY &&
      process.env.APNS_TOPIC,
  );
}

export async function sendVoIPPush(
  deviceToken: string,
  environment: APNsEnvironment,
  payload: VoIPPush,
): Promise<APNsResult> {
  const topic = process.env.APNS_TOPIC;
  if (!topic) throw new Error("APNS_TOPIC is not configured");
  const authorization = `bearer ${providerToken()}`;

  const origin =
    environment === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
  const body = JSON.stringify({
    aps: { "content-available": 1 },
    call_id: payload.callId,
    agent_id: payload.agentId,
    agent_name: payload.agentName,
    agent_emoji: payload.agentEmoji,
    brief: payload.brief,
    ...(payload.deadline ? { deadline: payload.deadline } : {}),
  });

  return new Promise<APNsResult>((resolve, reject) => {
    const session = connect(origin);
    let settled = false;
    const finish = (result: APNsResult | Error) => {
      if (settled) return;
      settled = true;
      session.close();
      if (result instanceof Error) reject(result);
      else resolve(result);
    };

    session.once("error", (error) => finish(error));
    const request = session.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization,
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body),
      "apns-topic": topic,
      "apns-push-type": "voip",
      "apns-priority": "10",
      // A ringing call must never arrive after it is useful.
      "apns-expiration": "0",
      "apns-id": payload.callId,
    });

    let status = 0;
    let responseBody = "";
    request.setEncoding("utf8");
    request.setTimeout(6_000, () => {
      request.close();
      finish(new Error("APNs request timed out"));
    });
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    request.on("data", (chunk) => {
      responseBody += chunk;
    });
    request.on("end", () => {
      let reason: string | undefined;
      try {
        const parsed = responseBody ? JSON.parse(responseBody) : null;
        if (typeof parsed?.reason === "string") reason = parsed.reason;
      } catch {
        reason = responseBody || undefined;
      }
      finish({ ok: status === 200, status, reason });
    });
    request.once("error", (error) => finish(error));
    request.end(body);
  });
}
