import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
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
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const profile = await getProfile(auth.userId);
  if (!profile)
    return NextResponse.json(
      { error: "billing unavailable (migration 0005 pending)" },
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

// Test credit top-up — replaced by StoreKit purchase validation once the
// paid Apple developer account exists. Grants a fixed €5.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const profile = await getProfile(auth.userId);
  if (!profile)
    return NextResponse.json(
      { error: "billing unavailable (migration 0005 pending)" },
      { status: 503 },
    );

  const credit = profile.credit_cents + 500;
  await supabase()
    .from("profiles")
    .update({ credit_cents: credit })
    .eq("user_id", auth.userId);
  return NextResponse.json({ creditCents: credit });
}
