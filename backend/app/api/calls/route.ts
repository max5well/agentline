import { NextRequest, NextResponse } from "next/server";
import { requireAppSecret } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { summarizeCall } from "@/lib/summarize";

// The app POSTs the buffered transcript on hangup (ADR-4).
// Summary/intents are written inline by the summary worker.
export async function POST(req: NextRequest) {
  const denied = requireAppSecret(req);
  if (denied) return denied;

  const body = await req.json();
  const { agentId, provider, startedAt, endedAt, transcript } = body;
  if (!agentId || !provider || !startedAt) {
    return NextResponse.json(
      { error: "agentId, provider, startedAt required" },
      { status: 400 },
    );
  }

  const { data, error } = await supabase()
    .from("calls")
    .insert({
      agent_id: agentId,
      provider,
      started_at: startedAt,
      ended_at: endedAt ?? null,
      transcript: transcript ?? [],
      cost_cents: body.costCents ?? null,
    })
    .select("id, agents(name)")
    .single();
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });

  // Summarize inline; a failure here must never lose the call record.
  try {
    const agentName =
      (data.agents as unknown as { name: string })?.name ?? "Agent";
    const digest = await summarizeCall(agentName, transcript ?? []);
    if (digest) {
      await supabase()
        .from("calls")
        .update({ summary: digest.summary, intents: digest.intents })
        .eq("id", data.id);
    }
  } catch (e) {
    console.error("summary worker failed", e);
  }

  return NextResponse.json({ callId: data.id }, { status: 201 });
}

export async function GET(req: NextRequest) {
  const denied = requireAppSecret(req);
  if (denied) return denied;

  const agentId = req.nextUrl.searchParams.get("agentId");
  let query = supabase()
    .from("calls")
    .select(
      "id, agent_id, provider, started_at, ended_at, transcript, summary, intents, cost_cents",
    )
    .order("started_at", { ascending: false })
    .limit(50);
  if (agentId) query = query.eq("agent_id", agentId);

  const { data, error } = await query;
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ calls: data });
}
