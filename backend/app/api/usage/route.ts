import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import {
  getProfile,
  monthUsage,
  OVERAGE_CENTS_PER_MIN,
  PLAN_QUOTAS,
} from "@/lib/billing";

// Server-side usage + billing state for the Billing screen.
export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const profile = await getProfile(auth.userId);
  if (!profile)
    return NextResponse.json(
      { error: "billing unavailable" },
      { status: 503 },
    );

  const usage = await monthUsage(auth.userId);
  const quotas = PLAN_QUOTAS[profile.plan] ?? PLAN_QUOTAS.free;
  return NextResponse.json({
    plan: profile.plan,
    creditCents: profile.credit_cents,
    fast: { usedMinutes: usage.fastMinutes, quotaMinutes: quotas.fast },
    big: { usedMinutes: usage.bigMinutes, quotaMinutes: quotas.big },
    overageCentsPerMinute: OVERAGE_CENTS_PER_MIN,
  });
}
