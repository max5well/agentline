import { NextResponse } from "next/server";
import type { Session, User } from "@supabase/supabase-js";
import { displayNameFromMetadata } from "@/lib/user";

// The session shape the iOS app stores in the Keychain.
export function sessionResponse(session: Session, user: User) {
  return NextResponse.json({
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt: session.expires_at,
    userId: user.id,
    email: user.email ?? null,
    name: displayNameFromMetadata(user.user_metadata),
  });
}
