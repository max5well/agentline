import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";

export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (!email || !password)
    return NextResponse.json(
      { error: "email and password required" },
      { status: 400 },
    );

  const { data, error } = await supabase().auth.signInWithPassword({
    email,
    password,
  });
  if (error || !data.session || !data.user)
    return NextResponse.json(
      { error: "wrong email or password" },
      { status: 401 },
    );
  return sessionResponse(data.session, data.user);
}
