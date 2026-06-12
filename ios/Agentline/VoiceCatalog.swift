import Foundation

// Voice and style catalogs for the picker (DESIGN-SPEC §3.7). Mirrors
// lib/voices.ts on the backend: an agent stores one voice id from either
// provider; the backend maps it for whichever provider runs the call.

struct VoiceOption: Identifiable {
    let id: String     // provider voice id
    let label: String
    let blurb: String

    // OpenAI Realtime voices — native on the Big tier.
    static let openAI: [VoiceOption] = [
        .init(id: "marin", label: "Calm", blurb: "Warm, steady, reassuring"),
        .init(id: "cedar", label: "Bright", blurb: "Clear and energetic"),
        .init(id: "sage", label: "Gentle", blurb: "Soft-spoken and patient"),
        .init(id: "ash", label: "Deep", blurb: "Low, serious, deliberate"),
        .init(id: "coral", label: "Upbeat", blurb: "Friendly and lively"),
        .init(id: "verse", label: "Expressive", blurb: "Dynamic, animated delivery"),
        .init(id: "alloy", label: "Neutral", blurb: "Balanced and even"),
        .init(id: "ballad", label: "Smooth", blurb: "Melodic, lyrical flow"),
        .init(id: "echo", label: "Confident", blurb: "Crisp and assured"),
        .init(id: "shimmer", label: "Cheerful", blurb: "Light and sparkling"),
    ]

    // Gemini prebuilt voices — native on the Fast and Local tiers.
    static let gemini: [VoiceOption] = [
        .init(id: "Zephyr", label: "Zephyr", blurb: "Bright"),
        .init(id: "Puck", label: "Puck", blurb: "Upbeat"),
        .init(id: "Charon", label: "Charon", blurb: "Informative"),
        .init(id: "Kore", label: "Kore", blurb: "Firm"),
        .init(id: "Fenrir", label: "Fenrir", blurb: "Excitable"),
        .init(id: "Leda", label: "Leda", blurb: "Youthful"),
        .init(id: "Orus", label: "Orus", blurb: "Firm"),
        .init(id: "Aoede", label: "Aoede", blurb: "Breezy"),
        .init(id: "Callirrhoe", label: "Callirrhoe", blurb: "Easy-going"),
        .init(id: "Autonoe", label: "Autonoe", blurb: "Bright"),
        .init(id: "Enceladus", label: "Enceladus", blurb: "Breathy"),
        .init(id: "Iapetus", label: "Iapetus", blurb: "Clear"),
        .init(id: "Umbriel", label: "Umbriel", blurb: "Easy-going"),
        .init(id: "Algieba", label: "Algieba", blurb: "Smooth"),
        .init(id: "Despina", label: "Despina", blurb: "Smooth"),
        .init(id: "Erinome", label: "Erinome", blurb: "Clear"),
        .init(id: "Algenib", label: "Algenib", blurb: "Gravelly"),
        .init(id: "Rasalgethi", label: "Rasalgethi", blurb: "Informative"),
        .init(id: "Laomedeia", label: "Laomedeia", blurb: "Upbeat"),
        .init(id: "Achernar", label: "Achernar", blurb: "Soft"),
        .init(id: "Alnilam", label: "Alnilam", blurb: "Firm"),
        .init(id: "Schedar", label: "Schedar", blurb: "Even"),
        .init(id: "Gacrux", label: "Gacrux", blurb: "Mature"),
        .init(id: "Pulcherrima", label: "Pulcherrima", blurb: "Forward"),
        .init(id: "Achird", label: "Achird", blurb: "Friendly"),
        .init(id: "Zubenelgenubi", label: "Zubenelgenubi", blurb: "Casual"),
        .init(id: "Vindemiatrix", label: "Vindemiatrix", blurb: "Gentle"),
        .init(id: "Sadachbia", label: "Sadachbia", blurb: "Lively"),
        .init(id: "Sadaltager", label: "Sadaltager", blurb: "Knowledgeable"),
        .init(id: "Sulafat", label: "Sulafat", blurb: "Warm"),
    ]

    static let all: [VoiceOption] = openAI + gemini
}

// Curated delivery styles: one-tap voice_style prompts that combine with
// any base voice. The S2S models *perform* these — same voice, different
// person. Saved voice profiles are the user-authored version of this.
struct StylePreset: Identifiable {
    let id: String
    let name: String
    let prompt: String

    static let all: [StylePreset] = [
        .init(id: "mentor", name: "Warm mentor",
              prompt: "Speak slowly and warmly, like a trusted mentor. Reassuring, with thoughtful pauses."),
        .init(id: "drywit", name: "Dry wit",
              prompt: "Deadpan delivery, dry ironic humor, economical with words."),
        .init(id: "coach", name: "Hype coach",
              prompt: "High energy, fast pace, motivational. Celebrate small wins out loud."),
        .init(id: "anchor", name: "News anchor",
              prompt: "Crisp, neutral, perfectly articulated, steady broadcast pacing."),
        .init(id: "storyteller", name: "Storyteller",
              prompt: "Vivid and dramatic. Vary pace and volume to build tension; land the endings."),
        .init(id: "latenight", name: "Late-night radio",
              prompt: "Low, smooth, unhurried, intimate — a late-night radio host."),
        .init(id: "professor", name: "Professor",
              prompt: "Measured and precise, slightly digressive, fond of a good aside."),
        .init(id: "cafe", name: "Café friend",
              prompt: "Casual and chatty, laid-back, like catching up over coffee."),
        .init(id: "therapist", name: "Therapist",
              prompt: "Calm, validating, unhurried. Leave space after questions."),
        .init(id: "sergeant", name: "Drill sergeant",
              prompt: "Clipped, loud, commanding. Short imperative sentences."),
        .init(id: "noir", name: "Noir detective",
              prompt: "Low and gravelly, terse, world-weary, a touch theatrical."),
        .init(id: "focused", name: "Fast & focused",
              prompt: "Quick and efficient, no filler. Get straight to the point."),
        .init(id: "grandparent", name: "Grandparent",
              prompt: "Gentle, slow, fond. Sprinkle in life wisdom and little stories."),
        .init(id: "berlin", name: "Berlin native",
              prompt: "Relaxed Berlin attitude: direct, a bit cheeky, informal."),
    ]
}
