import { NextRequest, NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import {
  APP_BUNDLE_ID,
  APPLE_PLAN_PRODUCTS,
  decodeAppleJWS,
} from "@/lib/apple";

// App Store Server Notifications V2. Public endpoint — authenticity
// comes from Apple's JWS signature, so the unverified-bypass flag is
// deliberately NOT honored here. Users are matched via appAccountToken,
// which the app sets to the Supabase user id on every purchase.
// Configure the URL in App Store Connect once the paid account exists.
export async function POST(req: NextRequest) {
  const { signedPayload } = await req.json();
  if (typeof signedPayload !== "string")
    return NextResponse.json(
      { error: "signedPayload required" },
      { status: 400 },
    );

  let notification;
  try {
    notification = decodeAppleJWS(signedPayload) as unknown as {
      notificationType: string;
      data?: { signedTransactionInfo?: string; bundleId?: string };
    };
  } catch (e) {
    console.warn("apple notification rejected:", (e as Error).message);
    return NextResponse.json({ error: "invalid signature" }, { status: 401 });
  }

  const signedTx = notification.data?.signedTransactionInfo;
  if (!signedTx) return NextResponse.json({ ok: true });

  let tx;
  try {
    tx = decodeAppleJWS(signedTx);
  } catch {
    return NextResponse.json({ error: "invalid transaction" }, { status: 401 });
  }
  if (tx.bundleId !== APP_BUNDLE_ID || !tx.appAccountToken)
    return NextResponse.json({ ok: true });

  const planId = APPLE_PLAN_PRODUCTS[tx.productId];
  if (!planId) return NextResponse.json({ ok: true });

  const active =
    !tx.revocationDate && (!tx.expiresDate || tx.expiresDate > Date.now());
  const lapsed = ["EXPIRED", "REVOKE", "REFUND"].some((t) =>
    notification.notificationType.startsWith(t),
  );

  const { error } = await supabase()
    .from("profiles")
    .update({ plan: lapsed || !active ? "free" : planId })
    .eq("user_id", tx.appAccountToken);
  if (error) console.error("notification plan update failed:", error.message);

  return NextResponse.json({ ok: true });
}
