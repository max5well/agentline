import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { sessionResponse } from "@/lib/session";

// Exchanges a native Sign in with Apple (or Google) id_token for a
// Supabase session (ADR-6). The provider must list the app as an
// authorized client in the Supabase dashboard.
export async function POST(req: NextRequest) {
  const { provider, idToken, nonce } = await req.json();
  if (!["apple", "google"].includes(provider) || !idToken)
    return NextResponse.json(
      { error: "provider (apple|google) and idToken required" },
      { status: 400 },
    );

  const { data, error } = await supabase().auth.signInWithIdToken({
    provider,
    token: idToken,
    nonce,
  });
  if (error || !data.session || !data.user) {
    console.error("sso exchange failed", error?.message);
    return NextResponse.json({ error: "sign-in failed" }, { status: 401 });
  }
  return sessionResponse(data.session, data.user);
}
