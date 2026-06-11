import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";

// Email signup (ADR-6). Users are created pre-confirmed via the admin API
// so no confirmation-email infrastructure is needed; the response is a
// ready-to-use session. Open endpoint — no rate limiting yet.
export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (!email || !password)
    return NextResponse.json(
      { error: "email and password required" },
      { status: 400 },
    );
  if (password.length < 8)
    return NextResponse.json(
      { error: "password must be at least 8 characters" },
      { status: 400 },
    );

  const { error } = await supabase().auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) {
    const exists = error.message.toLowerCase().includes("already");
    return NextResponse.json(
      { error: exists ? "account already exists" : error.message },
      { status: exists ? 409 : 400 },
    );
  }

  const { data, error: loginError } = await supabase().auth.signInWithPassword({
    email,
    password,
  });
  if (loginError || !data.session || !data.user)
    return NextResponse.json(
      { error: "signup succeeded but login failed" },
      { status: 500 },
    );
  return sessionResponse(data.session, data.user);
}
