import { NextResponse } from "next/server";

// Public: the app needs the Supabase URL to run the Google web-OAuth flow
// (ASWebAuthenticationSession against /auth/v1/authorize). Not a secret.
export async function GET() {
  return NextResponse.json({ supabaseUrl: process.env.SUPABASE_URL ?? null });
}
