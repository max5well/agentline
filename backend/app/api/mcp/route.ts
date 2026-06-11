import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { listMCPTools } from "@/lib/mcp";

// MCP handoff connection (stage 1): one server per user. POST validates
// the server by listing its tools; the app then PATCHes the chosen tool.

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  if (!auth.userId)
    return NextResponse.json({ error: "user required" }, { status: 400 });

  const { data } = await supabase()
    .from("mcp_connections")
    .select("url, tool_name, server_name")
    .eq("user_id", auth.userId)
    .maybeSingle();
  return NextResponse.json({ connection: data ?? null });
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
    const { error } = await supabase()
      .from("mcp_connections")
      .upsert({
        user_id: auth.userId,
        url,
        auth_token: authToken ?? "",
        server_name: serverName,
        tool_name: null,
      });
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

  const { toolName } = await req.json();
  const { error } = await supabase()
    .from("mcp_connections")
    .update({ tool_name: toolName ?? null })
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
