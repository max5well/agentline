import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { getProfile } from "@/lib/billing";
import {
  APP_BUNDLE_ID,
  APPLE_CREDIT_PRODUCTS,
  APPLE_PLAN_PRODUCTS,
  AppleTransaction,
  decodeAppleJWS,
  higherPlan,
} from "@/lib/apple";

// StoreKit sync (decided 2026-06-13): the app POSTs signed transactions
// after a purchase, and its full current entitlements on launch/restore
// (fullSync). Plan = highest active subscription; consumables top up
// credit exactly once per transaction id.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { transactions, fullSync } = await req.json();
  if (!Array.isArray(transactions))
    return NextResponse.json(
      { error: "transactions[] required" },
      { status: 400 },
    );

  let plan: string | null = null;
  let creditAdded = 0;

  for (const jws of transactions) {
    let tx: AppleTransaction;
    try {
      tx = decodeAppleJWS(String(jws), { allowUnverified: true });
    } catch (e) {
      console.warn("apple jws rejected:", (e as Error).message);
      continue;
    }
    if (tx.bundleId !== APP_BUNDLE_ID || tx.revocationDate) continue;

    const isNew = await recordOnce(tx, auth.userId);

    const planId = APPLE_PLAN_PRODUCTS[tx.productId];
    if (planId && (!tx.expiresDate || tx.expiresDate > Date.now())) {
      plan = higherPlan(plan ?? "free", planId);
    }
    const credit = APPLE_CREDIT_PRODUCTS[tx.productId];
    if (credit && isNew) creditAdded += credit;
  }

  const profile = await getProfile(auth.userId);
  if (!profile)
    return NextResponse.json(
      { error: "billing unavailable (migration 0005 pending)" },
      { status: 503 },
    );

  // fullSync carries every current entitlement, so no active plan there
  // means the subscription lapsed.
  const nextPlan = plan ?? (fullSync ? "free" : profile.plan);
  const nextCredit = profile.credit_cents + creditAdded;
  if (nextPlan !== profile.plan || creditAdded > 0) {
    const { error } = await supabase()
      .from("profiles")
      .update({ plan: nextPlan, credit_cents: nextCredit })
      .eq("user_id", auth.userId);
    if (error)
      return NextResponse.json({ error: error.message }, { status: 500 });
  }
  return NextResponse.json({ plan: nextPlan, creditCents: nextCredit });
}

// Inserts the transaction into the ledger; false when already processed.
// A pre-0010 schema records nothing — plans stay idempotent, but credit
// grants are refused (no replay protection without the ledger).
async function recordOnce(
  tx: AppleTransaction,
  userId: string,
): Promise<boolean> {
  const { data, error } = await supabase()
    .from("apple_transactions")
    .upsert(
      {
        transaction_id: tx.transactionId,
        user_id: userId,
        product_id: tx.productId,
        type: tx.type,
        raw: tx,
      },
      { onConflict: "transaction_id", ignoreDuplicates: true },
    )
    .select("transaction_id");
  if (error) {
    console.warn(
      "apple ledger unavailable (run migration 0010?):",
      error.message,
    );
    return false;
  }
  return (data?.length ?? 0) > 0;
}
