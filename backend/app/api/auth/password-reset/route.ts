import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";

export async function POST(req: NextRequest) {
  const { email } = await req.json();
  if (!email) return NextResponse.json({ error: "email required" }, { status: 400 });

  // Always return the same response so this endpoint cannot enumerate accounts.
  await supabase().auth.resetPasswordForEmail(
    String(email).trim().toLowerCase(),
    { redirectTo: "agentline://reset-password" },
  );
  return NextResponse.json({ ok: true });
}
