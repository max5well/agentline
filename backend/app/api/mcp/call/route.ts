import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { callMCPToolForResult } from "@/lib/mcp";
import { loadCallTools, resolveToolName } from "@/lib/tools";

// Executes one tool call from a live voice session (ADR-7). The app relays
// the model's function call here; the raw MCP credentials stay on the
// backend, exactly as API keys do (ADR-3).

// A spoken answer can't carry a 50 KB document, and the result is fed back
// into the model's context mid-call.
const MAX_RESULT_CHARS = 4000;

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { name, argumentsJSON } = await req.json();
  if (!name)
    return NextResponse.json({ error: "name required" }, { status: 400 });

  const connection = await loadCallTools(auth.userId);
  if (!connection)
    return NextResponse.json({ error: "no tools connected" }, { status: 400 });

  // The model sends the sanitized name; only tools the user allowed in
  // calls resolve, so a hallucinated name can't reach the server.
  const toolName = resolveToolName(name, connection.tools);
  if (!toolName)
    return NextResponse.json(
      { result: `No tool named ${name} is available.`, isError: true },
      { status: 200 },
    );

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let args: Record<string, any> = {};
  if (typeof argumentsJSON === "string" && argumentsJSON.trim()) {
    try {
      const parsed = JSON.parse(argumentsJSON);
      if (parsed && typeof parsed === "object") args = parsed;
    } catch {
      return NextResponse.json(
        {
          result: "The arguments were not valid JSON. Try calling it again.",
          isError: true,
        },
        { status: 200 },
      );
    }
  }

  const startedAt = Date.now();
  try {
    const result = await callMCPToolForResult(
      connection.url,
      connection.authToken,
      toolName,
      args,
    );
    logToolCall(auth.userId, toolName, true, Date.now() - startedAt);
    return NextResponse.json({
      result: result.slice(0, MAX_RESULT_CHARS),
      isError: false,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "tool call failed";
    console.error("in-call tool failed", toolName, message);
    logToolCall(auth.userId, toolName, false, Date.now() - startedAt);
    // 200 on purpose: the model should hear that the tool failed and say so,
    // rather than the app treating it as a broken session.
    return NextResponse.json({
      result: `The tool failed: ${message.slice(0, 300)}`,
      isError: true,
    });
  }
}

// Fire-and-forget: tool latency and failure rate are the numbers that decide
// whether in-call tools feel instant or broken (events table, migration 0009).
function logToolCall(
  userId: string,
  tool: string,
  ok: boolean,
  ms: number,
): void {
  void supabase()
    .from("events")
    .insert({
      user_id: userId,
      type: "tool_call",
      meta: { tool, ok, ms },
    })
    .then(({ error }) => {
      if (error) console.warn("tool_call event insert failed:", error.message);
    });
}
