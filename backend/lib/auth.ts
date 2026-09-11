import { NextRequest, NextResponse } from "next/server";
import { supabase } from "./supabase";
import { displayNameFromMetadata } from "./user";

// All data routes require a verified Supabase access token. Never fall back to
// an application-wide secret: that mode cannot scope rows to a user and would
// expose every account's data if enabled in a multi-user deployment.
export async function requireUser(
  req: NextRequest,
): Promise<NextResponse | { userId: string; callerName: string | null }> {
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const [scheme, token, extra] = authorization.trim().split(/\s+/);
  if (scheme?.toLowerCase() !== "bearer" || !token || extra) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { data, error } = await supabase().auth.getUser(token);
  if (error || !data.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  return {
    userId: data.user.id,
    callerName: displayNameFromMetadata(data.user.user_metadata),
  };
}
