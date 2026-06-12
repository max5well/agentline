import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { getProfile } from "@/lib/billing";

// Generic webhook target: any URL receives the call digest after every
// call — covers Zapier, Make, n8n, and home-grown automation.

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });
  const profile = await getProfile(auth.userId);
  return NextResponse.json({ url: profile?.webhook_url ?? null });
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { url } = await req.json();
  const { error } = await supabase()
    .from("profiles")
    .update({ webhook_url: url || null })
    .eq("user_id", auth.userId);
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
