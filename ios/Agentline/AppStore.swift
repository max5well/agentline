import SwiftUI

// Shared app state for the tab architecture: every tab reads the same
// agents and call records. Live data when the backend is configured,
// sample fixtures otherwise (demo mode).
@MainActor
@Observable
final class AppStore {
    var agents: [Agent]
    var records: [CallRecord]

    // With a backend configured, start from the last fetch (cached on
    // disk) instead of sample fixtures — otherwise the samples flash for
    // a second on every launch until load() returns. Samples remain the
    // demo-mode data set.
    init() {
        if Self.backendIfConfigured() != nil {
            agents = Self.readCache("agents.json") ?? []
            records = Self.readCache("records.json") ?? []
        } else {
            agents = Agent.samples
            records = CallRecord.samples
        }
    }

    static func backendIfConfigured() -> BackendClient? {
        let config = BackendConfig.current
        return config.isConfigured ? BackendClient(config: config) : nil
    }

    // Real provider when the backend is configured, mock otherwise. The
    // tier picks the provider, mirroring MODEL_BY_TIER on the backend:
    // big → OpenAI Realtime, fast/local → Gemini Live (until PersonaPlex).
    static func makeSession(for agent: Agent) -> any VoiceSession {
        guard let backend = backendIfConfigured() else { return MockVoiceSession() }
        return agent.tier == .big
            ? OpenAIRealtimeSession(backend: backend)
            : GeminiLiveSession(backend: backend)
    }

    func load() async {
        guard let backend = Self.backendIfConfigured() else { return }
        if let fetched = try? await backend.agents(), !fetched.isEmpty {
            agents = fetched
            Self.writeCache(fetched, to: "agents.json")
        }
        if let fetched = try? await backend.calls() {
            records = fetched
            Self.writeCache(fetched, to: "records.json")
        }
        cacheAgentsForSiri()
    }

    // MARK: - Launch cache (caches directory, JSON)

    private static func cacheURL(_ name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    private static func readCache<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: cacheURL(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func writeCache<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: cacheURL(name), options: .atomic)
        }
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL("agents.json"))
        try? FileManager.default.removeItem(at: cacheURL("records.json"))
    }

    // Siri's AgentEntityQuery resolves names from this cache, so "Call
    // Maya" works without the app running.
    private func cacheAgentsForSiri() {
        let cached = agents.map { AgentEntityQuery.CachedAgent(id: $0.id, name: $0.name) }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: "cachedAgents")
        }
    }

    func save(_ agent: Agent) {
        if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[idx] = agent
        } else {
            agents.append(agent)
        }
        if let backend = Self.backendIfConfigured() {
            Task { try? await backend.saveAgent(agent) }
        }
        cacheAgentsForSiri()
    }

    func agent(for record: CallRecord) -> Agent {
        agents.first { $0.id == record.agentId }
            ?? Agent(id: record.agentId, name: "Unknown", emoji: "👤", persona: "", voice: "marin", tier: .fast, language: nil, memoryEnabled: false)
    }

    // Spend this calendar month, for Settings/Billing.
    var spentThisMonthCents: Int {
        let calendar = Calendar.current
        return records
            .filter { calendar.isDate($0.startedAt, equalTo: .now, toGranularity: .month) }
            .compactMap(\.costCents)
            .reduce(0, +)
    }
}
