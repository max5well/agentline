import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { OPENAI_FROM_GEMINI, resolveOpenAIVoice } from "@/lib/voices";

// Renders a short voice sample so the picker and voice-profile editor
// can preview voices (DESIGN-SPEC §3.7/§3.8). OpenAI voices render via
// OpenAI TTS, Gemini prebuilt voices via Gemini TTS so the preview is
// the real sound; `style` carries the voice-profile prompt as delivery
// instructions on both.
const SAMPLE =
  "Hey! This is how I sound. Ready when you are — just start talking.";

// TTS voice catalog differs slightly from realtime; map any miss.
const FALLBACK: Record<string, string> = {
  marin: "sage",
  cedar: "nova",
};

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;

  const { voice, style, text } = await req.json();
  if (!voice)
    return NextResponse.json({ error: "voice required" }, { status: 400 });
  // Style presets ship an in-character sample line — a generic sentence
  // makes every style sound alike.
  const sample =
    typeof text === "string" && text.trim() ? text.slice(0, 200) : SAMPLE;

  if (voice in OPENAI_FROM_GEMINI && process.env.GEMINI_API_KEY) {
    const wav = await geminiTTS(voice, sample, style);
    if (wav) {
      return new NextResponse(new Uint8Array(wav), {
        status: 200,
        headers: {
          "Content-Type": "audio/wav",
          "Cache-Control": "private, max-age=3600",
        },
      });
    }
    // fall through to the OpenAI approximation
  }

  const openaiVoice = resolveOpenAIVoice(voice);
  let res = await openaiTTS(openaiVoice, sample, style);
  if (res.status === 400 && FALLBACK[openaiVoice]) {
    res = await openaiTTS(FALLBACK[openaiVoice], sample, style);
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

function openaiTTS(voice: string, sample: string, style?: string) {
  return fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini-tts",
      voice,
      input: sample,
      ...(style ? { instructions: `Performance style: ${style}` } : {}),
    }),
  });
}

// Gemini TTS returns raw 24 kHz 16-bit mono PCM; wrap it in a WAV header
// for AVAudioPlayer. Style goes into the prompt (natural-language control).
async function geminiTTS(
  voice: string,
  sample: string,
  style?: string,
): Promise<Buffer | null> {
  const prompt = style
    ? `Read this exactly once, performed ${style}: ${sample}`
    : `Say: ${sample}`;
  const res = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent",
    {
      method: "POST",
      headers: {
        "x-goog-api-key": process.env.GEMINI_API_KEY!,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } },
          },
        },
      }),
    },
  );
  if (!res.ok) {
    console.error("gemini tts failed", res.status, await res.text());
    return null;
  }
  const json = await res.json();
  const b64 = json?.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;
  if (!b64) return null;
  return wav(Buffer.from(b64, "base64"), 24000);
}

function wav(pcm: Buffer, sampleRate: number): Buffer {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16); // fmt chunk size
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28); // byte rate
  header.writeUInt16LE(2, 32); // block align
  header.writeUInt16LE(16, 34); // bits per sample
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}
