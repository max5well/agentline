import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";

// Renders a short voice sample so the picker and voice-profile editor
// can preview voices (DESIGN-SPEC §3.7/§3.8). Uses OpenAI TTS — the
// realtime voices are available there too; `style` carries the
// voice-profile prompt as delivery instructions.
const SAMPLE =
  "Hey Max! This is how I sound. Ready when you are — just start talking.";

// TTS voice catalog differs slightly from realtime; map any miss.
const FALLBACK: Record<string, string> = {
  marin: "sage",
  cedar: "nova",
};

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const { voice, style } = await req.json();
  if (!voice)
    return NextResponse.json({ error: "voice required" }, { status: 400 });

  let res = await tts(voice, style);
  if (res.status === 400 && FALLBACK[voice]) {
    res = await tts(FALLBACK[voice], style);
  }
  if (!res.ok) {
    console.error("voice preview failed", res.status, await res.text());
    return NextResponse.json({ error: "preview failed" }, { status: 502 });
  }

  return new NextResponse(res.body, {
    status: 200,
    headers: {
      "Content-Type": "audio/mpeg",
      "Cache-Control": "private, max-age=3600",
    },
  });
}

function tts(voice: string, style?: string) {
  return fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini-tts",
      voice,
      input: SAMPLE,
      ...(style ? { instructions: style } : {}),
    }),
  });
}
