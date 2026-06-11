import { NextRequest, NextResponse } from "next/server";
import { requireAppSecret } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

const MODEL_BY_TIER: Record<string, string> = {
  fast: "gpt-realtime-mini",
  big: "gpt-realtime",
};

// Mints a short-lived OpenAI Realtime client secret for one call,
// with the agent's persona baked into the session (ADR-3).
export async function POST(req: NextRequest) {
  const denied = requireAppSecret(req);
  if (denied) return denied;

  const { agentId } = await req.json();
  if (!agentId)
    return NextResponse.json({ error: "agentId required" }, { status: 400 });

  const { data: agent, error } = await supabase()
    .from("agents")
    .select("*")
    .eq("id", agentId)
    .single();
  if (error || !agent)
    return NextResponse.json({ error: "agent not found" }, { status: 404 });

  const model = MODEL_BY_TIER[agent.tier] ?? MODEL_BY_TIER.fast;

  const res = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      expires_after: { anchor: "created_at", seconds: 600 },
      session: {
        type: "realtime",
        model,
        instructions: agent.persona,
        audio: {
          input: { transcription: { model: "whisper-1" } },
          output: { voice: agent.voice },
        },
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    console.error("client_secrets failed", res.status, body);
    return NextResponse.json(
      { error: "token minting failed" },
      { status: 502 },
    );
  }

  const secret = await res.json();
  return NextResponse.json({
    clientSecret: secret.value,
    expiresAt: secret.expires_at,
    model,
    provider: "openai-realtime",
  });
}
