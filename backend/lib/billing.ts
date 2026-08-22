import { supabase } from "@/lib/supabase";

// Tiers and pay-as-you-go (decided 2026-06-12): paid plans continue past
// their included minutes on prepaid credit and hard-stop only when the
// credit is empty; Free hard-stops at its quota and never draws credit.
// Local-tier calls are free on every plan.

export type TierClass = "fast" | "big" | "local";

// Monthly prices; Stripe integration pending, so these are reference/
// display values until then.
export const PLAN_PRICE_CENTS: Record<string, number> = {
  free: 0,
  plus: 999,
  pro: 2499,
  max: 8999,
};

// Whether a plan may continue past its quota on prepaid credit.
export function canUseCredit(plan: string): boolean {
  return plan !== "free";
}

export const OVERAGE_CENTS_PER_MIN: Record<TierClass, number> = {
  fast: 10,
  big: 40,
  local: 0,
};

// Included minutes per month; null = unlimited.
export const PLAN_QUOTAS: Record<
  string,
  { fast: number | null; big: number | null }
> = {
  free: { fast: 30, big: 0 },
  plus: { fast: 240, big: 20 },
  pro: { fast: 600, big: 120 },
  max: { fast: null, big: 500 },
};

export function classOf(model: string | null, provider?: string): TierClass {
  if (model === "personaplex-7b") return "local";
  if (
    model?.startsWith("gemini") ||
    model === "gpt-realtime-mini" ||
    model === "gpt-realtime-2.1-mini"
  )
    return "fast";
  if (
    model === "gpt-realtime" ||
    model === "gpt-realtime-1.5" ||
    model === "gpt-realtime-2" ||
    model === "gpt-realtime-2.1"
  )
    return "big";
  // Legacy rows without a model column: infer from provider.
  if (provider === "gemini-live") return "fast";
  return "big";
}

export interface Profile {
  plan: string;
  credit_cents: number;
  webhook_url?: string | null;
}

// Lazily creates the row; tolerates a pre-0005 schema by treating the
// user as unmetered (the pre-billing behavior).
export async function getProfile(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase()
    .from("profiles")
    .select("plan, credit_cents, webhook_url")
    .eq("user_id", userId)
    .maybeSingle<Profile>();
  if (error) {
    console.warn("profiles unavailable (run migration 0005?):", error.message);
    return null;
  }
  if (data) return data;
  const fresh = { plan: "free", credit_cents: 0 };
  await supabase()
    .from("profiles")
    .insert({ user_id: userId, ...fresh });
  return fresh;
}

export interface MonthUsage {
  fastMinutes: number;
  bigMinutes: number;
}

export async function monthUsage(userId: string): Promise<MonthUsage> {
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  const { data } = await supabase()
    .from("calls")
    .select("started_at, ended_at, model, provider")
    .eq("user_id", userId)
    .gte("started_at", monthStart.toISOString())
    .limit(2000);

  let fast = 0;
  let big = 0;
  for (const call of data ?? []) {
    if (!call.ended_at) continue;
    const minutes =
      (new Date(call.ended_at).getTime() -
        new Date(call.started_at).getTime()) /
      60_000;
    const cls = classOf(call.model, call.provider);
    if (cls === "fast") fast += minutes;
    else if (cls === "big") big += minutes;
  }
  return { fastMinutes: fast, bigMinutes: big };
}

// Remaining included minutes for a class; null = unlimited.
export function remainingQuota(
  plan: string,
  cls: TierClass,
  usage: MonthUsage,
): number | null {
  if (cls === "local") return null;
  const quotas = PLAN_QUOTAS[plan] ?? PLAN_QUOTAS.free;
  const quota = quotas[cls];
  if (quota === null) return null;
  const used = cls === "fast" ? usage.fastMinutes : usage.bigMinutes;
  return Math.max(0, quota - used);
}
