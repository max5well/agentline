import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { distillMemory, summarizeCall } from "@/lib/summarize";
import { classOf, getProfile, monthUsage, remainingQuota, OVERAGE_CENTS_PER_MIN } from "@/lib/billing";
import { callMCPTool } from "@/lib/mcp";

// The app POSTs the buffered transcript on hangup (ADR-4).
// Summary/intents are written inline by the summary worker.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const body = await req.json();
  const { agentId, provider, startedAt, endedAt, transcript } = body;
  if (!agentId || !provider || !startedAt) {
    return NextResponse.json(
      { error: "agentId, provider, startedAt required" },
      { status: 400 },
    );
  }

  // The call must reference the caller's own agent.
  if (auth.userId) {
    const { data: agent } = await supabase()
      .from("agents")
      .select("user_id")
      .eq("id", agentId)
      .maybeSingle();
    if (!agent || agent.user_id !== auth.userId)
      return NextResponse.json({ error: "not your agent" }, { status: 403 });
  }

  const row: Record<string, unknown> = {
    agent_id: agentId,
    provider,
    started_at: startedAt,
    ended_at: endedAt ?? null,
    transcript: transcript ?? [],
    cost_cents: body.costCents ?? null,
  };
  if (auth.userId) row.user_id = auth.userId;
  if (body.model) row.model = body.model;

  const { data, error } = await supabase()
    .from("calls")
    .insert(row)
    .select("id")
    .single();
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });

  // Summarize inline; a failure here must never lose the call record.
  // (Separate agent fetch so a pre-0004 schema can't break the insert.)
  try {
    const { data: agent } = await supabase()
      .from("agents")
      .select("name, memory_file, memory_enabled")
      .eq("id", agentId)
      .maybeSingle<{ name: string; memory_file: string | null; memory_enabled: boolean }>();
    const agentName = agent?.name ?? "Agent";
    const digest = await summarizeCall(agentName, transcript ?? []);
    if (digest) {
      await supabase()
        .from("calls")
        .update({ summary: digest.summary, intents: digest.intents })
        .eq("id", data.id);
      // MCP handoff (stage 1): push the digest to the user's chosen tool.
      if (auth.userId) {
        const { data: mcp } = await supabase()
          .from("mcp_connections")
          .select("url, auth_token, tool_name")
          .eq("user_id", auth.userId)
          .maybeSingle();
        if (mcp?.tool_name) {
          try {
            await callMCPTool(mcp.url, mcp.auth_token, mcp.tool_name, {
              title: `Call with ${agentName}`,
              date: startedAt,
              summary: digest.summary,
              actionItems: digest.intents,
              transcript: (transcript ?? [])
                .map((e: { role: string; text: string }) =>
                  `${e.role === "user" ? "Max" : agentName}: ${e.text}`)
                .join("\n"),
            });
          } catch (e) {
            console.error("MCP handoff failed", e);
          }
        }
      }

      // Roll the call into the agent's memory file (DESIGN-SPEC §3.10).
      // Trivial calls carry no memory-worthy signal — skip the distill.
      if (agent?.memory_enabled && !digest.trivial) {
        const file = await distillMemory(
          agentName,
          agent.memory_file ?? "",
          digest.summary,
        );
        if (file) {
          await supabase()
            .from("agents")
            .update({ memory_file: file })
            .eq("id", agentId);
        }
      }
    }
  } catch (e) {
    console.error("summary worker failed", e);
  }

  // Overage: the part of this call beyond the monthly quota draws the
  // prepaid credit at the published per-minute rate.
  try {
    if (auth.userId && endedAt) {
      const profile = await getProfile(auth.userId);
      const cls = classOf((body.model as string) ?? null, provider);
      if (profile && cls !== "local") {
        const callMinutes =
          (new Date(endedAt).getTime() - new Date(startedAt).getTime()) / 60_000;
        // Usage already includes this call (inserted above).
        const usage = await monthUsage(auth.userId);
        const used = cls === "fast" ? usage.fastMinutes : usage.bigMinutes;
        const usedBefore = used - callMinutes;
        const remainingBefore = remainingQuota(
          profile.plan, cls,
          cls === "fast"
            ? { fastMinutes: usedBefore, bigMinutes: 0 }
            : { fastMinutes: 0, bigMinutes: usedBefore },
        );
        if (remainingBefore !== null) {
          const billableMinutes = Math.max(0, callMinutes - remainingBefore);
          const charge = Math.ceil(billableMinutes * OVERAGE_CENTS_PER_MIN[cls]);
          if (charge > 0) {
            await supabase()
              .from("profiles")
              .update({ credit_cents: Math.max(0, profile.credit_cents - charge) })
              .eq("user_id", auth.userId);
          }
        }
      }
    }
  } catch (e) {
    console.error("overage billing failed", e);
  }

  return NextResponse.json({ callId: data.id }, { status: 201 });
}

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const agentId = req.nextUrl.searchParams.get("agentId");
  let query = supabase()
    .from("calls")
    .select(
      "id, agent_id, provider, started_at, ended_at, transcript, summary, intents, cost_cents",
    )
    .order("started_at", { ascending: false })
    .limit(50);
  if (auth.userId) query = query.eq("user_id", auth.userId);
  if (agentId) query = query.eq("agent_id", agentId);

  const { data, error } = await query;
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ calls: data });
}

// Recents supports row deletion (DESIGN-SPEC §3.2).
export async function DELETE(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const id = req.nextUrl.searchParams.get("id");
  if (!id) return NextResponse.json({ error: "id required" }, { status: 400 });

  let query = supabase().from("calls").delete().eq("id", id);
  if (auth.userId) query = query.eq("user_id", auth.userId);

  const { error } = await query;
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
