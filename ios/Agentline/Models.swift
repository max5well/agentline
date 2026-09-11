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
    /// In-call MCP tools (ADR-7). Optional so rows from a pre-0011 backend
    /// still decode; nil reads as off.
    var toolsEnabled: Bool? = nil

    var usesTools: Bool { toolsEnabled ?? false }

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
        case toolsEnabled = "tools_enabled"
    }
}

// Minimal JSON tree. The Gemini setup message is assembled with
// JSONSerialization, so the function declarations the backend mints have to
// survive Codable and come back out as plain Foundation objects.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Foundation representation for JSONSerialization. Explicit returns:
    /// the branches have different types, which a switch expression can't
    /// unify even with `Any` as the declared result.
    var raw: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .object(let v): return v.mapValues(\.raw)
        case .array(let v): return v.map(\.raw)
        case .null: return NSNull()
        }
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
