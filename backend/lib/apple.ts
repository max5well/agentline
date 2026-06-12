import { X509Certificate, verify as cryptoVerify } from "node:crypto";

// Apple In-App Purchase (decided 2026-06-13): StoreKit 2 in the app,
// signed transactions (JWS) synced to /api/billing/apple, App Store
// Server Notifications V2 for renewals. Stripe never enters; Apple is
// the checkout.

export const APP_BUNDLE_ID = "dev.max5well.Agentline";

export const APPLE_PLAN_PRODUCTS: Record<string, string> = {
  "dev.max5well.agentline.plus": "plus",
  "dev.max5well.agentline.pro": "pro",
  "dev.max5well.agentline.max": "max",
};

export const APPLE_CREDIT_PRODUCTS: Record<string, number> = {
  "dev.max5well.agentline.credit5": 500,
  "dev.max5well.agentline.credit10": 1000,
  "dev.max5well.agentline.credit20": 2000,
};

const PLAN_RANK: Record<string, number> = { free: 0, plus: 1, pro: 2, max: 3 };

export function higherPlan(a: string, b: string): string {
  return (PLAN_RANK[a] ?? 0) >= (PLAN_RANK[b] ?? 0) ? a : b;
}

// Decoded JWSTransaction fields we use.
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId?: string;
  productId: string;
  bundleId: string;
  type: string;
  purchaseDate?: number; // ms epoch
  expiresDate?: number; // ms epoch, subscriptions only
  appAccountToken?: string;
  environment?: string;
  revocationDate?: number;
}

// Verifies an App Store JWS (ES256, x5c chain rooted at Apple) and
// returns the decoded payload. Set APPLE_IAP_ALLOW_UNVERIFIED=1 to skip
// signature checks — required while testing against Xcode's local
// StoreKit environment, whose transactions Apple's chain can't sign.
// The server-notification endpoint never allows the bypass.
export function decodeAppleJWS(
  jws: string,
  { allowUnverified = false } = {},
): AppleTransaction {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const [h, p, s] = parts;
  const header = JSON.parse(Buffer.from(h, "base64url").toString());
  const payload = JSON.parse(Buffer.from(p, "base64url").toString());

  if (allowUnverified && process.env.APPLE_IAP_ALLOW_UNVERIFIED === "1") {
    return payload;
  }

  const chain: X509Certificate[] = (header.x5c ?? []).map(
    (c: string) => new X509Certificate(Buffer.from(c, "base64")),
  );
  if (chain.length < 2) throw new Error("missing certificate chain");
  // Each certificate must be signed by the next one up.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey))
      throw new Error("broken certificate chain");
  }
  const root = chain[chain.length - 1];
  if (!root.subject.includes("Apple Root CA"))
    throw new Error("chain does not end at Apple");
  const ok = cryptoVerify(
    "sha256",
    Buffer.from(`${h}.${p}`),
    { key: chain[0].publicKey, dsaEncoding: "ieee-p1363" },
    Buffer.from(s, "base64url"),
  );
  if (!ok) throw new Error("bad signature");
  return payload;
}
