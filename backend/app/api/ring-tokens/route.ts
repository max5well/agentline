import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { apnsConfigured } from "@/lib/apns";
import { createRingToken } from "@/lib/ring-auth";
import { supabase } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const [tokenResult, deviceResult] = await Promise.all([
    supabase()
      .from("ring_api_tokens")
      .select("token_prefix, created_at, last_used_at")
      .eq("user_id", auth.userId)
      .is("revoked_at", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase()
      .from("voip_devices")
      .select("token", { count: "exact", head: true })
      .eq("user_id", auth.userId),
  ]);
  if (tokenResult.error || deviceResult.error) {
    return NextResponse.json(
      { error: tokenResult.error?.message ?? deviceResult.error?.message },
      { status: 500 },
    );
  }
  const token = tokenResult.data;

  return NextResponse.json({
    token: token
      ? {
          prefix: token.token_prefix,
          createdAt: token.created_at,
          lastUsedAt: token.last_used_at,
        }
      : null,
    deviceCount: deviceResult.count ?? 0,
    apnsConfigured: apnsConfigured(),
  });
}

// Create/rotate the one active token. The plaintext is returned exactly once.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const generated = createRingToken();
  const now = new Date().toISOString();
  const { error } = await supabase().rpc("rotate_ring_api_token", {
    p_user_id: auth.userId,
    p_token_hash: generated.hash,
    p_token_prefix: generated.prefix,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  return NextResponse.json(
    { token: generated.token, prefix: generated.prefix, createdAt: now },
    { status: 201 },
  );
}

export async function DELETE(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const { error } = await supabase()
    .from("ring_api_tokens")
    .update({ revoked_at: new Date().toISOString() })
    .eq("user_id", auth.userId)
    .is("revoked_at", null);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
