import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { listMCPTools } from "@/lib/mcp";

// MCP connection: one server per user. POST validates the server by listing
// its tools and caches that list on the row. The app then PATCHes both the
// digest target (tool_name, stage 1) and the tools the agent may use during
// a call (call_tools, ADR-7).

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { data } = await supabase()
    .from("mcp_connections")
    .select("url, tool_name, server_name, tools_json, call_tools")
    .eq("user_id", auth.userId)
    .maybeSingle();
  if (!data) return NextResponse.json({ connection: null });

  const { tools_json, ...connection } = data;
  return NextResponse.json({
    connection: { ...connection, tools: tools_json ?? [] },
  });
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { url, authToken } = await req.json();
  if (!url)
    return NextResponse.json({ error: "url required" }, { status: 400 });

  try {
    const { serverName, tools } = await listMCPTools(url, authToken ?? "");
    // Cache the list: /api/realtime/token reads it on every call start and
    // must not pay for a round trip to the MCP server there.
    const row: Record<string, unknown> = {
      user_id: auth.userId,
      url,
      auth_token: authToken ?? "",
      server_name: serverName,
      tool_name: null,
      tools_json: tools,
    };
    let { error } = await supabase().from("mcp_connections").upsert(row);
    if (error && /tools_json/.test(error.message)) {
      // Pre-0011 schema: connecting still works, in-call tools stay off.
      console.warn("mcp_connections has no tools_json (run migration 0011?)");
      delete row.tools_json;
      ({ error } = await supabase().from("mcp_connections").upsert(row));
    }
    if (error)
      return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ serverName, tools });
  } catch (e) {
    return NextResponse.json(
      {
        error:
          e instanceof Error ? e.message : "Could not reach the MCP server",
      },
      { status: 502 },
    );
  }
}

export async function PATCH(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const body = await req.json();
  const update: Record<string, unknown> = {};
  // Two independent settings, so only the ones actually sent are written:
  // picking call tools must not clear the digest target, or the reverse.
  if ("toolName" in body) update.tool_name = body.toolName ?? null;
  if ("callTools" in body) {
    update.call_tools = Array.isArray(body.callTools)
      ? body.callTools.filter((t: unknown) => typeof t === "string")
      : null;
  }
  if (Object.keys(update).length === 0)
    return NextResponse.json({ ok: true });

  const { error } = await supabase()
    .from("mcp_connections")
    .update(update)
    .eq("user_id", auth.userId);
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  await supabase().from("mcp_connections").delete().eq("user_id", auth.userId);
  return NextResponse.json({ ok: true });
}
