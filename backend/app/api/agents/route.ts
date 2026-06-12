import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  let query = supabase()
    .from("agents")
    .select("*")
    .order("created_at", { ascending: true });
  if (auth.userId) query = query.eq("user_id", auth.userId);

  const { data, error } = await query;
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ agents: data });
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const body = await req.json();
  const { name, persona } = body;
  if (!name || !persona) {
    return NextResponse.json(
      { error: "name and persona required" },
      { status: 400 },
    );
  }

  // Upsert: the app creates agents with its own UUID and edits them
  // through the same endpoint — so an existing id must belong to the caller.
  if (body.id && auth.userId) {
    const { data: existing } = await supabase()
      .from("agents")
      .select("user_id")
      .eq("id", body.id)
      .maybeSingle();
    if (existing && existing.user_id !== auth.userId)
      return NextResponse.json({ error: "not your agent" }, { status: 403 });
  }

  const row: Record<string, unknown> = {
    name,
    persona,
    emoji: body.emoji ?? "🤖",
    voice: body.voice ?? "marin",
    tier: body.tier ?? "fast",
    language: body.language ?? "English",
    memory_enabled: body.memory_enabled ?? true,
    updated_at: new Date().toISOString(),
  };
  if (body.id) row.id = body.id;
  if (auth.userId) row.user_id = auth.userId;
  // Migration 0003 columns — only written when the app sends them, so the
  // route keeps working against a database that hasn't run 0003 yet.
  if (body.voice_style !== undefined) row.voice_style = body.voice_style;
  if (body.memory_file !== undefined) row.memory_file = body.memory_file;
  if (body.avatar_url !== undefined) row.avatar_url = body.avatar_url;
  if (body.color !== undefined) row.color = body.color;
  if (body.model !== undefined) row.model = body.model;

  const { data, error } = await supabase()
    .from("agents")
    .upsert(row)
    .select()
    .single();
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ agent: data }, { status: 201 });
}
