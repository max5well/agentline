import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

const TOKEN_PATTERN = /^[0-9a-f]{64,256}$/;

export async function PUT(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const body = await req.json().catch(() => null);
  const token = typeof body?.token === "string" ? body.token.toLowerCase() : "";
  const environment = body?.environment;
  if (
    !TOKEN_PATTERN.test(token) ||
    (environment !== "sandbox" && environment !== "production")
  ) {
    return NextResponse.json({ error: "invalid device registration" }, { status: 400 });
  }

  const { error } = await supabase().from("voip_devices").upsert(
    {
      token,
      user_id: auth.userId,
      environment,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "token" },
  );
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const body = await req.json().catch(() => null);
  const token = typeof body?.token === "string" ? body.token.toLowerCase() : "";
  if (!TOKEN_PATTERN.test(token)) {
    return NextResponse.json({ error: "invalid device token" }, { status: 400 });
  }

  const { error } = await supabase()
    .from("voip_devices")
    .delete()
    .eq("token", token)
    .eq("user_id", auth.userId);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
