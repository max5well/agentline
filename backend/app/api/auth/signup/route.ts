import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";
import { clientAddress, consumeSignupRateLimit } from "@/lib/rate-limit";

export async function POST(req: NextRequest) {
  const { email, password, name } = await req.json();
  if (!email || !password)
    return NextResponse.json({ error: "email and password required" }, { status: 400 });
  if (password.length < 8)
    return NextResponse.json({ error: "password must be at least 8 characters" }, { status: 400 });

  const normalizedEmail = String(email).trim().toLowerCase();
  const normalizedName =
    typeof name === "string"
      ? name.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 80)
      : "";
  try {
    const [ipAllowed, emailAllowed] = await Promise.all([
      consumeSignupRateLimit("ip", clientAddress(req), 10, 3600),
      consumeSignupRateLimit("email", normalizedEmail, 3, 3600),
    ]);
    if (!ipAllowed || !emailAllowed) {
      return NextResponse.json(
        { error: "Too many signup attempts. Try again later." },
        { status: 429, headers: { "Retry-After": "3600" } },
      );
    }
  } catch (error) {
    console.error("signup rate limit unavailable", error);
    return NextResponse.json(
      { error: "Signup is temporarily unavailable. Try again shortly." },
      { status: 503 },
    );
  }

  const { data, error } = await supabase().auth.signUp({
    email: normalizedEmail,
    password,
    options: {
      emailRedirectTo: "agentline://auth-callback",
      data: normalizedName
        ? { display_name: normalizedName, full_name: normalizedName }
        : undefined,
    },
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
  if (!data.user) {
    return NextResponse.json({ error: "signup returned no user" }, { status: 500 });
  }
  return sessionResponse(data.session, data.user);
}
