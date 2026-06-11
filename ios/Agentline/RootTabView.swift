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

// 3-tab information architecture (DESIGN-SPEC §2).
struct RootTabView: View {
    enum Tab { case agents, recents, settings }

    @State private var store = AppStore()
    @State private var tab: Tab = .agents
    @State private var activeCall: Agent?
    @State private var editing: AgentEditTarget?
    @State private var showTemplates = false
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            AgentsListView(store: store, activeCall: $activeCall, editing: $editing, showTemplates: $showTemplates)
                .tabItem { Label("Agents", systemImage: "person.2") }
                .tag(Tab.agents)
            RecentsView(store: store)
                .tabItem { Label("Recents", systemImage: "clock") }
                .tag(Tab.recents)
            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .fullScreenCover(item: $activeCall, onDismiss: {
            // Pick up the record (and summary) of the call that just ended.
            Task { await store.load() }
        }) { agent in
            CallView(agent: agent, session: AppStore.makeSession(for: agent))
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
            // First run only; never during UI-test hooks.
            if !hasOnboarded && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-") }) {
                showOnboarding = true
                hasOnboarded = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startCallIntent)) { note in
            // Siri / App Intents: "Call Maya" (#27).
            guard let id = note.object as? UUID,
                  let agent = store.agents.first(where: { $0.id == id }) else { return }
            activeCall = agent
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme ?? nil)
    }

    // UI-test hooks: jump straight to a screen so simctl can screenshot it.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-autocall") {
            // Presenting a cover during the initial transition gets dropped.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                activeCall = store.agents.first
            }
        } else if args.contains("-screen-history") {
            tab = .recents
        } else if args.contains("-screen-settings") {
            tab = .settings
        } else if args.contains("-screen-editor") {
            editing = AgentEditTarget(agent: store.agents.first)
        }
    }
}

// Distinguishes "new agent" from "edit agent" for the sheet item.
struct AgentEditTarget: Identifiable {
    let id = UUID()
    let agent: Agent?
}
