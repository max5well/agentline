import AppIntents
import Foundation

// Siri / Shortcuts: "Call Maya in agentline" — hands-free call start
// while walking or driving. The intent opens the app and RootTabView
// presents the call.

extension Notification.Name {
    static let startCallIntent = Notification.Name("startCallIntent")
}

struct AgentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Agent"
    static let defaultQuery = AgentEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// Agents are cached by AppStore on every load, so Siri can resolve
// names without the app running.
struct AgentEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AgentEntity] {
        Self.cached().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AgentEntity] {
        Self.cached()
    }

    static func cached() -> [AgentEntity] {
        guard let data = UserDefaults.standard.data(forKey: "cachedAgents"),
              let agents = try? JSONDecoder().decode([CachedAgent].self, from: data) else { return [] }
        return agents.map { AgentEntity(id: $0.id, name: $0.name) }
    }

    struct CachedAgent: Codable {
        let id: UUID
        let name: String
    }
}

struct CallAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Call Agent"
    static let description = IntentDescription("Start a voice call with one of your agents.")
    static let openAppWhenRun = true

    @Parameter(title: "Agent")
    var agent: AgentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .startCallIntent, object: agent.id)
        return .result()
    }
}

struct AgentlineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CallAgentIntent(),
            phrases: [
                "Call \(\.$agent) in \(.applicationName)",
                "Call \(\.$agent) on \(.applicationName)",
                "\(.applicationName) call \(\.$agent)",
            ],
            shortTitle: "Call Agent",
            systemImageName: "phone.fill"
        )
    }
}
