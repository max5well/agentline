import SwiftUI

// Shared app state for the tab architecture: every tab reads the same
// agents and call records. Live data when the backend is configured,
// sample fixtures otherwise (demo mode).
@MainActor
@Observable
final class AppStore {
    var agents: [Agent] = Agent.samples
    var records: [CallRecord] = CallRecord.samples

    static func backendIfConfigured() -> BackendClient? {
        let config = BackendConfig.current
        return config.isConfigured ? BackendClient(config: config) : nil
    }

    // Real provider when the backend is configured, mock otherwise.
    // While GEMINI_API_KEY is unset on the backend, every tier falls back
    // to OpenAI there — mirror that here or fast-tier calls die on the
    // provider mismatch. Restore tier-based routing (big → OpenAI,
    // fast/local → GeminiLiveSession) once the key is configured.
    static func makeSession(for agent: Agent) -> any VoiceSession {
        guard let backend = backendIfConfigured() else { return MockVoiceSession() }
        return OpenAIRealtimeSession(backend: backend)
    }

    func load() async {
        guard let backend = Self.backendIfConfigured() else { return }
        if let fetched = try? await backend.agents(), !fetched.isEmpty {
            agents = fetched
        }
        if let fetched = try? await backend.calls() {
            records = fetched
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
