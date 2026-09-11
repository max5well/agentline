import { createHmac } from "node:crypto";
import { supabase } from "@/lib/supabase";

export function clientAddress(req: Request): string {
  const forwarded =
    req.headers.get("x-vercel-forwarded-for") ??
    req.headers.get("x-forwarded-for") ??
    "unknown";
  return forwarded.split(",", 1)[0]?.trim() || "unknown";
}

export async function consumeSignupRateLimit(
  scope: "ip" | "email",
  value: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret) throw new Error("rate-limit secret is not configured");
  const keyHash = createHmac("sha256", secret)
    .update(`signup:${scope}:${value}`)
    .digest("hex");
  const { data, error } = await supabase().rpc("consume_signup_rate_limit", {
    p_key_hash: keyHash,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) throw error;
  return data === true;
}
