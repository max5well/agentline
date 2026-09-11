import { createHash, randomBytes } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { supabase } from "./supabase";

const TOKEN_PREFIX = "al_ring_";

export function hashRingToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function createRingToken(): { token: string; hash: string; prefix: string } {
  const token = `${TOKEN_PREFIX}${randomBytes(32).toString("base64url")}`;
  return {
    token,
    hash: hashRingToken(token),
    prefix: `${token.slice(0, 16)}…`,
  };
}

export async function requireRingToken(
  req: NextRequest,
): Promise<NextResponse | { userId: string; tokenId: string }> {
  const authorization = req.headers.get("authorization");
  const [scheme, token, extra] = authorization?.trim().split(/\s+/) ?? [];
  if (
    scheme?.toLowerCase() !== "bearer" ||
    !token?.startsWith(TOKEN_PREFIX) ||
    extra
  ) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { data, error } = await supabase()
    .from("ring_api_tokens")
    .select("id, user_id")
    .eq("token_hash", hashRingToken(token))
    .is("revoked_at", null)
    .maybeSingle();

  if (error || !data) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // Usage metadata is best-effort and must not make a valid ring fail.
  const { error: updateError } = await supabase()
    .from("ring_api_tokens")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", data.id);
  if (updateError) console.warn("ring token usage update failed", updateError.message);

  return { userId: data.user_id, tokenId: data.id };
}
