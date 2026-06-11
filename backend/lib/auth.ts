import { NextRequest, NextResponse } from "next/server";

// Single-user app: every route checks a static shared secret (ADR-5).
export function requireAppSecret(req: NextRequest): NextResponse | null {
  const secret = process.env.APP_SECRET;
  if (!secret) {
    return NextResponse.json(
      { error: "APP_SECRET not configured" },
      { status: 500 },
    );
  }
  if (req.headers.get("x-app-secret") !== secret) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  return null;
}
