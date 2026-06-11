// Post-call summary worker (ADR-4). Runs inline on call save — serverless
// has no background workers without extra infra, and a few hundred ms on
// hangup is invisible to the user.
// ADR-4 names Claude Haiku for this slot; using gpt-4o-mini until an
// Anthropic key is configured.

type TranscriptEntry = { role: string; text: string; t: number };

export type CallDigest = { summary: string; intents: string[] };

export async function summarizeCall(
  agentName: string,
  transcript: TranscriptEntry[],
): Promise<CallDigest | null> {
  if (transcript.length === 0) return null;

  const lines = transcript
    .map((e) => `${e.role === "user" ? "Max" : agentName}: ${e.text}`)
    .join("\n");

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "You summarize a voice call between Max and an AI agent. " +
            'Reply with JSON: {"summary": string, "intents": string[]}. ' +
            "summary: 2-4 sentences, past tense, what was discussed and concluded. " +
            "intents: concrete follow-ups or action items Max took away; empty array if none.",
        },
        { role: "user", content: lines },
      ],
    }),
  });
  if (!res.ok) {
    console.error("summarize failed", res.status, await res.text());
    return null;
  }

  const body = await res.json();
  try {
    const digest = JSON.parse(body.choices[0].message.content);
    if (typeof digest.summary !== "string") return null;
    return {
      summary: digest.summary,
      intents: Array.isArray(digest.intents) ? digest.intents : [],
    };
  } catch {
    return null;
  }
}
