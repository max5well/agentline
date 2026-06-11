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
    var memoryEnabled: Bool

    /// Comma-separated list in `language`; first entry is the default.
    var languages: [String] {
        (language ?? "English")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, persona, voice, tier, language, model
        case voiceStyle = "voice_style"
        case memoryEnabled = "memory_enabled"
    }
}

struct TranscriptEntry: Codable, Hashable {
    let role: String // "user" | "agent"
    let text: String
    let t: TimeInterval // seconds since call start
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

    enum CodingKeys: String, CodingKey {
        case id, provider, transcript, summary, intents
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
