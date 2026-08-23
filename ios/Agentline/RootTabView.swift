import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// Two-task information architecture: configure/start agents, then review calls.
// Settings stays available from the Agents toolbar without competing for a tab.
struct RootTabView: View {
    enum Tab { case agents, calls }

    @State private var store = AppStore()
    @State private var tab: Tab = .agents
    @State private var preparingCall: Agent?
    @State private var activeCall: PreparedCall?
    @State private var editing: AgentEditTarget?
    @State private var completedAgentId: UUID?
    @State private var reviewingCall: CallRecord?
    @State private var showTemplates = false
    @State private var showSettings = false
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            AgentsListView(
                store: store,
                preparingCall: $preparingCall,
                editing: $editing,
                showTemplates: $showTemplates,
                showSettings: $showSettings
            )
            .tabItem { Label("Agents", systemImage: "person.2") }
            .tag(Tab.agents)

            RecentsView(store: store)
                .tabItem { Label("Calls", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.calls)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
        .sheet(item: $preparingCall) { agent in
            CallPreparationView(
                agent: agent,
                lastCall: store.records.first { $0.agentId == agent.id }
            ) { objective in
                preparingCall = nil
                Task { @MainActor in
                    await Task.yield()
                    completedAgentId = agent.id
                    activeCall = PreparedCall(agent: agent, objective: objective)
                }
            }
        }
        .fullScreenCover(item: $activeCall, onDismiss: {
            Task {
                await store.load()
                if let agentId = completedAgentId {
                    reviewingCall = store.records
                        .filter { $0.agentId == agentId }
                        .max { $0.startedAt < $1.startedAt }
                }
                completedAgentId = nil
            }
        }) { prepared in
            CallView(
                agent: prepared.agent,
                objective: prepared.objective,
                session: AppStore.makeSession(for: prepared.agent, objective: prepared.objective)
            )
        }
        .sheet(item: $reviewingCall) { record in
            NavigationStack {
                CallSummaryView(record: record, agent: store.agent(for: record))
            }
        }
        .sheet(item: $editing) { target in
            AgentEditorView(agent: target.agent, records: store.records) { store.save($0) }
        }
        .sheet(isPresented: $showTemplates) {
            TemplateGalleryView { store.save($0) }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showTemplates = true }
        }
        .task { await store.load() }
        .onAppear(perform: handleLaunchArguments)
        .onAppear {
            if !hasOnboarded && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-") }) {
                showOnboarding = true
                hasOnboarded = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startCallIntent)) { note in
            guard let id = note.object as? UUID,
                  let agent = store.agents.first(where: { $0.id == id }) else { return }
            completedAgentId = agent.id
            activeCall = PreparedCall(agent: agent, objective: nil)
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme ?? nil)
    }

    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-autocall") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                if let agent = store.agents.first {
                    completedAgentId = agent.id
                    activeCall = PreparedCall(agent: agent, objective: nil)
                }
            }
        } else if args.contains("-screen-history") || args.contains("-screen-calls") {
            tab = .calls
        } else if args.contains("-screen-settings") {
            showSettings = true
        } else if args.contains("-screen-editor") {
            editing = AgentEditTarget(agent: store.agents.first)
        } else if args.contains("-screen-templates") {
            showTemplates = true
        }
    }
}

struct AgentEditTarget: Identifiable {
    let id = UUID()
    let agent: Agent?
}
