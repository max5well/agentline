import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import {
  canUseCredit,
  classOf,
  getProfile,
  monthUsage,
  remainingQuota,
} from "@/lib/billing";
import { resolveGeminiVoice, resolveOpenAIVoice } from "@/lib/voices";
import {
  loadCallTools,
  toGeminiTools,
  toOpenAITools,
  toolInstructions,
  type CallTools,
} from "@/lib/tools";

const GEMINI_31 = "gemini-3.1-flash-live-preview";
const GEMINI_25 = "gemini-2.5-flash-native-audio-preview-12-2025";
const OPENAI_FAST = "gpt-realtime-2.1-mini";
const OPENAI_SMART = "gpt-realtime-2.1";

// Gemini 3.1 is the primary Fast model. Set GEMINI_LIVE_MODEL to the 2.5
// model id for an instant rollback without shipping a new iOS build.
const configuredGemini =
  process.env.GEMINI_LIVE_MODEL === GEMINI_25 ? GEMINI_25 : GEMINI_31;

const MODEL_BY_TIER: Record<string, string> = {
  local: configuredGemini,
  fast: configuredGemini,
  big: OPENAI_SMART,
};

const ALLOWED_MODELS_BY_TIER: Record<string, Set<string>> = {
  local: new Set([GEMINI_31, GEMINI_25]),
  fast: new Set([GEMINI_31, GEMINI_25, OPENAI_FAST]),
  big: new Set([OPENAI_SMART]),
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function buildInstructions(agent: any, memory: string, objective: string): string {
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
  // Answer language is fixed; input language is free — Max may speak any
  // language he likes (e.g. to practice one) and still get answers in the
  // agent's language(s).
  const languageRule =
    languages.length > 1
      ? `Always answer in ${languages[0]} by default; you may switch your answers between ${languages.join(", ")} if Max explicitly asks or clearly switches, but answer in no other languages. Max may speak to you in any language — always understand him`
      : `Always answer in ${languages[0] ?? "English"}, no matter which language Max speaks to you in — he may use any language and you must understand him, but your replies stay in ${languages[0] ?? "English"} unless your persona explicitly requires another language`;
  const objectiveRule = objective
    ? `\n\nCurrent call objective: ${objective}. Help Max achieve it, periodically keep the conversation on track, and close with a concise recap and next step.`
    : "";
  const vocabulary = Array.isArray(agent.vocabulary)
    ? agent.vocabulary.filter((term: unknown) => typeof term === "string").slice(0, 100)
    : [];
  const vocabularyRule = vocabulary.length
    ? `\n\nReference vocabulary and pronunciations: ${vocabulary.join("; ")}. Preserve these spellings and pronunciations.`
    : "";
  const groundingRule = agent.web_grounding_enabled
    ? "\n\nFor claims that may have changed, use web search before answering. In the spoken answer, name the source and publication date naturally. Distinguish verified facts from inference and say when current information could not be confirmed."
    : "";
  return `${agent.persona}${style}\n\n${languageRule}. The caller is Max. Open the call by greeting him in one short, casual sentence, then let him lead.${objectiveRule}${vocabularyRule}${groundingRule}${memory}`;
}

// Mints a short-lived client credential for one call (ADR-3): an OpenAI
// Realtime client secret with the persona baked in server-side, or a Gemini
// ephemeral token plus the session config the app sends in its setup
// message. Either way the raw API key never leaves the backend.
export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const { agentId, objective: rawObjective } = await req.json();
  if (!agentId)
    return NextResponse.json({ error: "agentId required" }, { status: 400 });

  const objective =
    typeof rawObjective === "string"
      ? rawObjective.trim().slice(0, 500)
      : "";

  const { data: agent, error } = await supabase()
    .from("agents")
    .select("*")
    .eq("id", agentId)
    .single();
  if (error || !agent || (auth.userId && agent.user_id !== auth.userId))
    return NextResponse.json({ error: "agent not found" }, { status: 404 });

  const tierModel = MODEL_BY_TIER[agent.tier] ?? MODEL_BY_TIER.fast;
  const requestedModel = typeof agent.model === "string" ? agent.model : "";
  const allowedModels =
    ALLOWED_MODELS_BY_TIER[agent.tier] ?? ALLOWED_MODELS_BY_TIER.fast;
  const selectedModel = allowedModels.has(requestedModel)
    ? requestedModel
    : tierModel;
  // Gemini Live currently provides server-side Google Search grounding.
  const model = agent.web_grounding_enabled ? configuredGemini : selectedModel;
  const isGemini = model.startsWith("gemini");

  // Memory: inject summaries of the last calls with this agent so it can
  // pick up where the previous conversation left off.
  let memory = "";
  if (agent.memory_enabled && agent.memory_file) {
    memory = `\n\nWhat you remember about Max and your past conversations:\n${agent.memory_file}`;
  } else if (agent.memory_enabled) {
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

  // Quota gate: included minutes first, then prepaid credit on paid
  // plans, hard stop when both are gone (Free never draws credit).
  if (auth.userId) {
    const profile = await getProfile(auth.userId);
    if (profile) {
      const cls = classOf(model);
      const remaining = remainingQuota(
        profile.plan,
        cls,
        await monthUsage(auth.userId),
      );
      // Paid plans overflow onto prepaid credit; Free hard-stops at quota.
      const creditLeft = canUseCredit(profile.plan) && profile.credit_cents > 0;
      if (remaining !== null && remaining <= 0 && !creditLeft) {
        // The hit rate of this wall (especially plan=free) is the signal
        // for revisiting pay-as-you-go on Free. Tolerates a pre-0009 schema.
        await supabase()
          .from("events")
          .insert({
            user_id: auth.userId,
            type: "quota_exceeded",
            meta: { plan: profile.plan, class: cls },
          })
          .then(({ error: e }) => {
            if (e)
              console.warn(
                "event insert failed (run migration 0009?):",
                e.message,
              );
          });
        return NextResponse.json(
          {
            error: !canUseCredit(profile.plan)
              ? "You've used this month's free minutes. Upgrade in Billing to keep talking."
              : cls === "big"
                ? "You've used this month's big-brain minutes and your credit is empty. Add credit in Billing, or switch the agent to a fast model."
                : "You've used this month's included minutes and your credit is empty. Add credit in Billing to keep talking.",
            code: "quota_exceeded",
          },
          { status: 402 },
        );
      }
    }
  }

  // In-call tools (ADR-7): opt-in per agent, read from the tool list cached
  // on the connection so this adds no network round trip to call setup.
  const callTools = agent.tools_enabled
    ? await loadCallTools(auth.userId ?? null)
    : null;

  let instructions = buildInstructions(agent, memory, objective);
  if (callTools) instructions += toolInstructions(callTools.tools);

  // Keep the Fast tier available when Gemini is not configured.
  if (isGemini && !process.env.GEMINI_API_KEY) {
    console.warn(`GEMINI_API_KEY not set, falling back to ${OPENAI_FAST}`);
    return mintOpenAI(OPENAI_FAST, instructions, agent.voice, callTools);
  }
  return isGemini
    ? mintGemini(model, instructions, agent.voice, callTools)
    : mintOpenAI(model, instructions, agent.voice, callTools);
}

async function mintOpenAI(
  model: string,
  instructions: string,
  rawVoice: string,
  callTools: CallTools | null = null,
) {
  const voice = resolveOpenAIVoice(rawVoice);
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
        // Baked into the secret like the persona, so the app never sees the
        // tool list and can't widen it (ADR-3).
        ...(callTools
          ? {
              tools: toOpenAITools(callTools.tools),
              tool_choice: "auto",
            }
          : {}),
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
    toolCount: callTools?.tools.length ?? 0,
  });
}

async function mintGemini(
  model: string,
  instructions: string,
  voice: string,
  callTools: CallTools | null = null,
) {
  if (!process.env.GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set");
    return NextResponse.json(
      { error: "Gemini is not configured on the backend" },
      { status: 502 },
    );
  }

  const expiresAt = Date.now() + 600_000;
  const res = await fetch(
    // Plain collection POST — the AIP-style ":create" suffix 404s here.
    "https://generativelanguage.googleapis.com/v1alpha/auth_tokens",
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
    // app needs these; OpenAI bakes them into the secret server-side. Same
    // for the function declarations — the app merges them with googleSearch.
    instructions,
    voice: resolveGeminiVoice(voice),
    tools: callTools ? toGeminiTools(callTools.tools) : null,
    toolCount: callTools?.tools.length ?? 0,
  });
}
