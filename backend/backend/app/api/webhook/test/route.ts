import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { getProfile } from "@/lib/billing";

// Sends a sample digest so the user can verify their automation.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const profile = await getProfile(auth.userId);
  if (!profile?.webhook_url)
    return NextResponse.json(
      { error: "No webhook configured" },
      { status: 400 },
    );

  try {
    const res = await fetch(profile.webhook_url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        event: "test",
        agent: "Test Agent",
        date: new Date().toISOString(),
        durationMinutes: 1,
        summary: "This is a test event from agentline.",
        actionItems: ["Confirm the webhook works"],
        transcript: [],
      }),
      signal: AbortSignal.timeout(5000),
    });
    return NextResponse.json({ ok: res.ok, status: res.status });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "delivery failed" },
      { status: 502 },
    );
  }
}
