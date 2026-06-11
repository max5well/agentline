import SwiftUI

struct ContactsView: View {
    @State private var agents: [Agent] = Agent.samples
    @State private var records: [CallRecord] = CallRecord.samples
    @State private var activeCall: Agent?
    @State private var editing: EditorTarget?
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case history
        case settings
    }

    // Distinguishes "new agent" from "edit agent" for the sheet item.
    struct EditorTarget: Identifiable {
        let id = UUID()
        let agent: Agent?
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                    if !recents.isEmpty {
                        sectionLabel("Recents")
                        VStack(spacing: 0) {
                            ForEach(recents, id: \.record.id) { item in
                                NavigationLink(value: item.record) {
                                    RecentRow(record: item.record, agent: item.agent)
                                }
                                if item.record.id != recents.last?.record.id {
                                    Divider().overlay(Color.white.opacity(0.075))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .glassCard()
                    }
                    sectionLabel("Agents")
                    VStack(spacing: 0) {
                        ForEach(agents) { agent in
                            // Row opens the editor; the phone button calls.
                            Button { editing = EditorTarget(agent: agent) } label: {
                                ContactRow(agent: agent) { activeCall = agent }
                            }
                            if agent.id != agents.last?.id {
                                Divider().overlay(Color.white.opacity(0.075))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassCard()
                }
                .padding(20)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history: HistoryView(records: records, agents: agents)
                case .settings: SettingsView()
                }
            }
            .navigationDestination(for: CallRecord.self) { record in
                CallSummaryView(record: record, agent: agent(for: record))
            }
            .fullScreenCover(item: $activeCall, onDismiss: {
                // Pick up the record (and summary) of the call that just ended.
                Task { await loadFromBackend() }
            }) { agent in
                CallView(agent: agent, session: Self.makeSession(for: agent))
            }
            .sheet(item: $editing) { target in
                AgentEditorView(agent: target.agent) { saved in
                    if let idx = agents.firstIndex(where: { $0.id == saved.id }) {
                        agents[idx] = saved
                    } else {
                        agents.append(saved)
                    }
                    if let backend = Self.backendIfConfigured() {
                        Task { try? await backend.saveAgent(saved) }
                    }
                }
            }
            .task { await loadFromBackend() }
            .onAppear(perform: handleLaunchArguments)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var navRow: some View {
        HStack(spacing: 10) {
            (Text("agent").foregroundStyle(Theme.text) + Text("line").foregroundStyle(Theme.accent))
                .font(.system(size: 34, weight: .bold))
                .kerning(-1.2)
            Spacer()
            circleButton("clock.arrow.circlepath") { path.append(Route.history) }
            circleButton("gearshape") { path.append(Route.settings) }
            circleButton("plus") { editing = EditorTarget(agent: nil) }
        }
        .padding(.bottom, 12)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(1.4)
            .foregroundStyle(Theme.text.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private var recents: [(record: CallRecord, agent: Agent)] {
        records.sorted { $0.startedAt > $1.startedAt }
            .prefix(2)
            .map { ($0, agent(for: $0)) }
    }

    private func agent(for record: CallRecord) -> Agent {
        agents.first { $0.id == record.agentId }
            ?? Agent(id: record.agentId, name: "Unknown", emoji: "👤", persona: "", voice: "marin", tier: .fast, language: nil, memoryEnabled: false)
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

    static func backendIfConfigured() -> BackendClient? {
        let config = BackendConfig.current
        return config.isConfigured ? BackendClient(config: config) : nil
    }

    // Live data when the backend is configured; sample fixtures otherwise.
    private func loadFromBackend() async {
        guard let backend = Self.backendIfConfigured() else { return }
        if let fetched = try? await backend.agents(), !fetched.isEmpty {
            agents = fetched
        }
        if let fetched = try? await backend.calls() {
            records = fetched
        }
    }

    // UI-test hooks: jump straight to a screen so simctl can screenshot it.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-autocall") {
            activeCall = agents.first
        } else if args.contains("-screen-history") {
            path.append(Route.history)
        } else if args.contains("-screen-settings") {
            path.append(Route.settings)
        } else if args.contains("-screen-summary"), let record = records.first {
            path.append(record)
        } else if args.contains("-screen-editor") {
            editing = EditorTarget(agent: agents.first)
        }
    }
}

struct ContactRow: View {
    let agent: Agent
    var onCall: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Text(agent.emoji).font(.system(size: 26))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(agent.persona.components(separatedBy: ".").first ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(agent.tier.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
                )

            Button(action: onCall) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: 0x17120C))
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }
}

struct RecentRow: View {
    let record: CallRecord
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Text(agent.emoji).font(.system(size: 26))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(agent.persona.components(separatedBy: ".").first ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeLabel)
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var timeLabel: String {
        if Calendar.current.isDateInToday(record.startedAt) {
            return record.startedAt.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(record.startedAt) {
            return "Yesterday"
        }
        return record.startedAt.formatted(.dateTime.weekday(.abbreviated))
    }
}
