import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { pushDigestToMCPTool } from "@/lib/mcp";

// Manual (re-)push of one call to the connected MCP tool — the "Send
// via MCP" row on the call summary. The automatic push happens on hangup.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { callId } = await req.json();
  if (!callId)
    return NextResponse.json({ error: "callId required" }, { status: 400 });

  const { data: mcp } = await supabase()
    .from("mcp_connections")
    .select("url, auth_token, tool_name")
    .eq("user_id", auth.userId)
    .maybeSingle();
  if (!mcp?.tool_name)
    return NextResponse.json(
      { error: "No MCP tool connected" },
      { status: 400 },
    );

  const { data: call } = await supabase()
    .from("calls")
    .select("started_at, transcript, summary, intents, agents(name)")
    .eq("id", callId)
    .eq("user_id", auth.userId)
    .maybeSingle();
  if (!call)
    return NextResponse.json({ error: "call not found" }, { status: 404 });

  const agentName =
    (call.agents as unknown as { name: string })?.name ?? "Agent";
  const caller = auth.callerName ?? "Caller";
  try {
    await pushDigestToMCPTool(mcp.url, mcp.auth_token, mcp.tool_name, {
      title: `Call with ${agentName}`,
      date: call.started_at,
      summary: call.summary ?? "",
      actionItems: call.intents ?? [],
      transcript: ((call.transcript as { role: string; text: string }[]) ?? [])
        .map((e) => `${e.role === "user" ? caller : agentName}: ${e.text}`)
        .join("\n"),
    });
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "MCP push failed" },
      { status: 502 },
    );
  }
}
