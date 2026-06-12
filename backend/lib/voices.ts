// Voice catalogs and cross-provider mapping. Agents store one voice id —
// either an OpenAI Realtime voice or a Gemini prebuilt voice — and the
// token/preview routes resolve it for whichever provider actually runs
// the call. Mirrors VoiceCatalog.swift in the app.

export const OPENAI_VOICES = new Set([
  "alloy",
  "ash",
  "ballad",
  "cedar",
  "coral",
  "echo",
  "marin",
  "sage",
  "shimmer",
  "verse",
]);

// OpenAI id → closest Gemini prebuilt voice.
export const GEMINI_FROM_OPENAI: Record<string, string> = {
  alloy: "Iapetus", // neutral, clear
  ash: "Charon", // deep, serious
  ballad: "Algieba", // smooth, melodic
  cedar: "Zephyr", // bright, energetic
  coral: "Puck", // upbeat, friendly
  echo: "Kore", // crisp, firm
  marin: "Aoede", // calm, warm
  sage: "Achernar", // gentle, soft
  shimmer: "Sadachbia", // light, lively
  verse: "Fenrir", // expressive, dynamic
};

// Gemini prebuilt voice → closest OpenAI Realtime voice (by published
// descriptor). Doubles as the catalog of valid Gemini voice ids.
export const OPENAI_FROM_GEMINI: Record<string, string> = {
  Zephyr: "cedar", // bright
  Puck: "coral", // upbeat
  Charon: "ash", // informative
  Kore: "echo", // firm
  Fenrir: "verse", // excitable
  Leda: "shimmer", // youthful
  Orus: "echo", // firm
  Aoede: "marin", // breezy
  Callirrhoe: "marin", // easy-going
  Autonoe: "cedar", // bright
  Enceladus: "sage", // breathy
  Iapetus: "alloy", // clear
  Umbriel: "marin", // easy-going
  Algieba: "ballad", // smooth
  Despina: "ballad", // smooth
  Erinome: "alloy", // clear
  Algenib: "ash", // gravelly
  Rasalgethi: "echo", // informative
  Laomedeia: "coral", // upbeat
  Achernar: "sage", // soft
  Alnilam: "ash", // firm
  Schedar: "alloy", // even
  Gacrux: "ash", // mature
  Pulcherrima: "verse", // forward
  Achird: "coral", // friendly
  Zubenelgenubi: "coral", // casual
  Vindemiatrix: "sage", // gentle
  Sadachbia: "shimmer", // lively
  Sadaltager: "echo", // knowledgeable
  Sulafat: "marin", // warm
};

export function resolveGeminiVoice(voice: string): string {
  if (voice in OPENAI_FROM_GEMINI) return voice; // already a Gemini id
  return GEMINI_FROM_OPENAI[voice] ?? "Puck";
}

export function resolveOpenAIVoice(voice: string): string {
  if (OPENAI_VOICES.has(voice)) return voice;
  return OPENAI_FROM_GEMINI[voice] ?? "marin";
}
