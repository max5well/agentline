import Foundation

enum Tier: String, Codable, CaseIterable {
    case local, fast, big

    var label: String { rawValue.capitalized }
}

struct Agent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var emoji: String
    var persona: String
    var voice: String
    var tier: Tier
    // Optionals with defaults so rows from a pre-migration backend still
    // decode and existing initializer call sites keep compiling.
    var language: String?
    /// Delivery/style prompt ("slow, warm, slight British accent").
    var voiceStyle: String? = nil
    /// Explicit model override; nil = derived from tier on the backend.
    var model: String? = nil
    /// Distilled rolling memory, written by the backend after each call.
    var memoryFile: String? = nil
    /// Photo or generated avatar in the avatars bucket; nil = emoji/monogram.
    var avatarUrl: String? = nil
    /// Avatar background color name (AgentPalette); nil = derived from id.
    var color: String? = nil
    var memoryEnabled: Bool
    /// User-provided spellings and pronunciations for names and specialist terms.
    var vocabulary: [String]? = nil
    /// Route current-information calls through a grounded provider.
    var webGroundingEnabled: Bool? = false

    /// Comma-separated list in `language`; first entry is the default.
    var languages: [String] {
        (language ?? "English")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, persona, voice, tier, language, model, color
        case voiceStyle = "voice_style"
        case memoryFile = "memory_file"
        case avatarUrl = "avatar_url"
        case memoryEnabled = "memory_enabled"
        case vocabulary
        case webGroundingEnabled = "web_grounding_enabled"
    }
}

// Model catalog (DESIGN-SPEC §3.9): the UI exposes model ids; the tier
// stays as the derived grouping the backend routes on.
struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let tier: Tier
    var available: Bool = true
}

enum ModelCatalog {
    static let all: [ModelOption] = [
        .init(id: "personaplex-7b", name: "PersonaPlex 7B",
              blurb: "Runs on your Mac Studio · most natural turn-taking",
              tier: .local, available: false),
        .init(id: "custom-local", name: "Your own model",
              blurb: "Hook up a self-hosted voice model",
              tier: .local, available: false),
        .init(id: "gemini-3.1-flash-live-preview", name: "Gemini 3.1 Flash Live",
              blurb: "Fast, natural everyday conversations", tier: .fast),
        .init(id: "gpt-realtime-2.1-mini", name: "GPT Realtime 2.1 Mini",
              blurb: "Efficient OpenAI voice fallback", tier: .fast),
        .init(id: "gemini-2.5-flash-native-audio-preview-12-2025", name: "Gemini 2.5 Flash Live",
              blurb: "Compatibility rollback", tier: .fast, available: false),
        .init(id: "gpt-realtime-2.1", name: "GPT Realtime 2.1",
              blurb: "Smartest voice reasoning and tool use", tier: .big),
        .init(id: "claude-sonnet-pipeline", name: "Claude Sonnet (pipeline)",
              blurb: "Deepest reasoning · +~200ms latency",
              tier: .big, available: false),
    ]

    static func option(for agent: Agent) -> ModelOption? {
        if let model = agent.model, let exact = all.first(where: { $0.id == model }) {
            return exact
        }
        // Tier default mirrors the backend's MODEL_BY_TIER.
        switch agent.tier {
        case .local, .fast: return all.first { $0.id == "gemini-3.1-flash-live-preview" }
        case .big: return all.first { $0.id == "gpt-realtime-2.1" }
        }
    }
}

extension Agent {
    var modelDisplayName: String {
        ModelCatalog.option(for: self)?.name ?? model ?? tier.label
    }
}

struct TranscriptEntry: Codable, Hashable {
    let role: String // "user" | "agent"
    let text: String
    let t: TimeInterval // seconds since call start
}

struct CallFeedback: Codable, Hashable {
    var latency: Int
    var voice: Int
    var accuracy: Int
    var usefulness: Int
}

struct CallRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let agentId: UUID
    let provider: String
    let startedAt: Date
    let endedAt: Date?
    let transcript: [TranscriptEntry]
    let summary: String?
    let intents: [String]?
    let costCents: Int?
    let objective: String? = nil
    let feedback: CallFeedback? = nil

    enum CodingKeys: String, CodingKey {
        case id, provider, transcript, summary, intents, objective, feedback
        case agentId = "agent_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case costCents = "cost_cents"
    }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var durationLabel: String {
        guard let duration else { return "—" }
        return "\(max(1, Int(duration / 60)))m"
    }
}
