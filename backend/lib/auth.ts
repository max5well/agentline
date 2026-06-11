import { NextRequest, NextResponse } from "next/server";
import { supabase } from "./supabase";

// ADR-6: data routes authenticate with a Supabase Auth bearer JWT and are
// scoped to that user. The legacy x-app-secret header (ADR-5) is still
// accepted during the transition and maps to the unscoped pre-auth rows
// (user_id null) — delete APP_SECRET from the env to retire it.
//
// Returns a NextResponse to short-circuit with, or the caller's identity:
// userId is null in legacy mode, which skips user scoping entirely.
export async function requireUser(
  req: NextRequest,
): Promise<NextResponse | { userId: string | null }> {
  const bearer = req.headers.get("authorization");
  if (bearer?.startsWith("Bearer ")) {
    const { data, error } = await supabase().auth.getUser(bearer.slice(7));
    if (!error && data.user) return { userId: data.user.id };
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const secret = process.env.APP_SECRET;
  if (secret && req.headers.get("x-app-secret") === secret) {
    return { userId: null };
  }
  return NextResponse.json({ error: "unauthorized" }, { status: 401 });
}
