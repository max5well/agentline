import { NextRequest, NextResponse } from "next/server";
import { requireAppSecret } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

const MODEL_BY_TIER: Record<string, string> = {
  fast: "gpt-realtime-mini",
  big: "gpt-realtime",
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function buildInstructions(agent: any, memory: string): string {
  const style = agent.voice_style
    ? `\n\nVoice and delivery: ${agent.voice_style}`
    : "";
  // Without a language anchor the model sometimes guesses the
  // language from the first noisy audio frames. `language` may hold a
  // comma-separated list; the first entry is the default.
  const languages = (agent.language ?? "English")
    .split(",")
    .map((l: string) => l.trim())
    .filter(Boolean);
  const languageRule =
    languages.length > 1
      ? `Speak ${languages[0]} by default. You may switch between ${languages.join(", ")} if Max does, but no other languages`
      : `Always speak ${languages[0] ?? "English"}, unless your persona explicitly requires another language`;
  return `${agent.persona}${style}\n\n${languageRule}. The caller is Max. Open the call by greeting him in one short, casual sentence, then let him lead.${memory}`;
}

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

  const model =
    agent.model || (MODEL_BY_TIER[agent.tier] ?? MODEL_BY_TIER.fast);

  // Memory: inject summaries of the last calls with this agent so it can
  // pick up where the previous conversation left off.
  let memory = "";
  if (agent.memory_enabled) {
    const { data: recent } = await supabase()
      .from("calls")
      .select("summary, started_at")
      .eq("agent_id", agentId)
      .not("summary", "is", null)
      .order("started_at", { ascending: false })
      .limit(3);
    if (recent && recent.length > 0) {
      const bullets = recent
        .map((c) => `- (${new Date(c.started_at).toDateString()}) ${c.summary}`)
        .join("\n");
      memory = `\n\nWhat you remember from your recent calls with Max, most recent first:\n${bullets}`;
    }
  }

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
        instructions: buildInstructions(agent, memory),
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
