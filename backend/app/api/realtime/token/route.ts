import { NextRequest, NextResponse } from "next/server";
import { requireAppSecret } from "@/lib/auth";
import { supabase } from "@/lib/supabase";

// Tier → model (ADR-2): fast is the cheap Gemini Live tier, big is full
// OpenAI Realtime, local rides Gemini until PersonaPlexSession exists.
// The provider is derived from the model name; the app derives its session
// implementation from the tier the same way, so a per-agent model override
// must stay within the tier's provider family (enforced below).
const MODEL_BY_TIER: Record<string, string> = {
  local: "gemini-2.5-flash-native-audio-preview-12-2025",
  fast: "gemini-2.5-flash-native-audio-preview-12-2025",
  big: "gpt-realtime",
};

// Agents store OpenAI voice ids; map each to the closest Gemini prebuilt
// voice so one agent config works on both providers.
const GEMINI_VOICE: Record<string, string> = {
  marin: "Aoede", // calm, warm
  cedar: "Zephyr", // bright, energetic
  sage: "Achernar", // gentle, soft
  ash: "Charon", // deep, serious
  coral: "Puck", // upbeat, friendly
  verse: "Fenrir", // expressive, dynamic
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

// Mints a short-lived client credential for one call (ADR-3): an OpenAI
// Realtime client secret with the persona baked in server-side, or a Gemini
// ephemeral token plus the session config the app sends in its setup
// message. Either way the raw API key never leaves the backend.
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

  const tierModel = MODEL_BY_TIER[agent.tier] ?? MODEL_BY_TIER.fast;
  const isGemini = tierModel.startsWith("gemini");
  const override = typeof agent.model === "string" ? agent.model : "";
  const model =
    override && override.startsWith("gemini") === isGemini
      ? override
      : tierModel;

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

  const instructions = buildInstructions(agent, memory);
  // Until GEMINI_API_KEY is configured, Gemini tiers fall back to the
  // OpenAI mini flow so calls keep working (the pre-Gemini behavior).
  if (isGemini && !process.env.GEMINI_API_KEY) {
    console.warn("GEMINI_API_KEY not set, falling back to gpt-realtime-mini");
    return mintOpenAI("gpt-realtime-mini", instructions, agent.voice);
  }
  return isGemini
    ? mintGemini(model, instructions, agent.voice)
    : mintOpenAI(model, instructions, agent.voice);
}

async function mintOpenAI(model: string, instructions: string, voice: string) {
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
        instructions,
        audio: {
          input: { transcription: { model: "whisper-1" } },
          output: { voice },
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

async function mintGemini(model: string, instructions: string, voice: string) {
  if (!process.env.GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set");
    return NextResponse.json(
      { error: "Gemini is not configured on the backend" },
      { status: 502 },
    );
  }

  const expiresAt = Date.now() + 600_000;
  const res = await fetch(
    "https://generativelanguage.googleapis.com/v1alpha/auth_tokens:create",
    {
      method: "POST",
      headers: {
        "x-goog-api-key": process.env.GEMINI_API_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        uses: 1,
        expireTime: new Date(expiresAt).toISOString(),
        // Window in which the app must open the websocket.
        newSessionExpireTime: new Date(Date.now() + 120_000).toISOString(),
      }),
    },
  );

  if (!res.ok) {
    const body = await res.text();
    console.error("auth_tokens:create failed", res.status, body);
    return NextResponse.json(
      { error: "token minting failed" },
      { status: 502 },
    );
  }

  const token = await res.json();
  return NextResponse.json({
    clientSecret: token.name,
    expiresAt: Math.floor(expiresAt / 1000),
    model,
    provider: "gemini-live",
    // Gemini sessions are configured by the client's setup message, so the
    // app needs these; OpenAI bakes them into the secret server-side.
    instructions,
    voice: GEMINI_VOICE[voice] ?? "Puck",
  });
}
