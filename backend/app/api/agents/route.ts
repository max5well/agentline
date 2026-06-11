import { NextRequest, NextResponse } from "next/server";
import { requireAppSecret } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const denied = requireAppSecret(req);
  if (denied) return denied;

  const { data, error } = await supabase()
    .from("agents")
    .select("*")
    .order("created_at", { ascending: true });
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ agents: data });
}

export async function POST(req: NextRequest) {
  const denied = requireAppSecret(req);
  if (denied) return denied;

  const body = await req.json();
  const { name, persona } = body;
  if (!name || !persona) {
    return NextResponse.json(
      { error: "name and persona required" },
      { status: 400 },
    );
  }

  const { data, error } = await supabase()
    .from("agents")
    .insert({
      name,
      persona,
      emoji: body.emoji ?? "🤖",
      voice: body.voice ?? "marin",
      tier: body.tier ?? "fast",
    })
    .select()
    .single();
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ agent: data }, { status: 201 });
}
