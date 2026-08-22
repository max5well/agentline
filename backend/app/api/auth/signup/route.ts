import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";

export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (!email || !password)
    return NextResponse.json({ error: "email and password required" }, { status: 400 });
  if (password.length < 8)
    return NextResponse.json({ error: "password must be at least 8 characters" }, { status: 400 });

  const { data, error } = await supabase().auth.signUp({
    email: String(email).trim().toLowerCase(),
    password,
    options: { emailRedirectTo: "agentline://auth-callback" },
  });
  if (error) {
    const exists = error.message.toLowerCase().includes("already");
    return NextResponse.json(
      { error: exists ? "account already exists" : error.message },
      { status: exists ? 409 : 400 },
    );
  }

  if (!data.session) {
    return NextResponse.json({
      confirmationRequired: true,
      email: data.user?.email ?? email,
    }, { status: 202 });
  }
  return sessionResponse(data.session, data.user);
}
