import SwiftUI

// Settings tab (DESIGN-SPEC §3.11).
struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("handoff.includeTranscript") private var shareTranscriptAfterCalls = false
    @AppStorage("defaultLanguage") private var defaultLanguage = "English"
    @State private var auth = AuthStore.shared
    @State private var connections = ToolConnections()
    @State private var connectingTool: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BillingView(store: store)
                    } label: {
                        HStack {
                            Label("Subscription & Billing", systemImage: "creditcard")
                            Spacer()
                            Text(String(format: "€%.2f this month", Double(store.spentThisMonthCents) / 100))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                    NavigationLink {
                        AnalyticsView(store: store)
                    } label: {
                        Label("Analytics", systemImage: "chart.bar")
                    }
                    Picker(selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    ForEach(ConnectedToolsStore.all) { tool in
                        toolRow(tool)
                    }
                    webhookRow
                    Toggle("Share transcript after calls", isOn: $shareTranscriptAfterCalls)
                } header: {
                    Text("Connected tools")
                } footer: {
                    Text("Connected tools appear as “Send to” options on every call summary. MCP also receives every call automatically.")
                }

                Section("Defaults") {
                    NavigationLink {
                        VoiceProfilesListView()
                    } label: {
                        HStack {
                            Label("Voice Profiles", systemImage: "waveform")
                            Spacer()
                            Text("\(VoiceProfileStore.load().count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        LanguagePickerView(selection: Binding(
                            get: { defaultLanguage }, set: { defaultLanguage = $0 ?? "English" }
                        ))
                    } label: {
                        HStack {
                            Label("Default Language", systemImage: "globe")
                            Spacer()
                            Text(defaultLanguage.components(separatedBy: ",").first ?? "English")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        BackendSettingsView()
                    } label: {
                        HStack {
                            Label("Backend", systemImage: "server.rack")
                            Spacer()
                            Text("● Connected")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if let session = auth.session {
                    Section("Account") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.email ?? "Signed in")
                                    .font(.body.weight(.medium))
                                Text("Agents and call history belong to this account.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign out") { auth.signOut() }
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                } footer: {
                    Text("agentline \(appVersion)\(BackendConfig.current.isConfigured ? "" : " · demo mode")")
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .task { await connections.refresh() }
            .sheet(item: Binding(
                get: { connectingTool.map { ToolSheetID(id: $0) } },
                set: { connectingTool = $0?.id }
            )) { sheet in
                switch sheet.id {
                case "obsidian":
                    ObsidianConnectSheet { Task { await connections.refresh() } }
                case "drive":
                    DriveConnectSheet { Task { await connections.refresh() } }
                case "webhook":
                    WebhookConnectSheet(existing: connections.webhookURL) {
                        Task { await connections.refresh() }
                    }
                default:
                    MCPConnectSheet(existing: connections.mcpConnection) {
                        Task { await connections.refresh() }
                    }
                }
            }
        }
    }

    private struct ToolSheetID: Identifiable { let id: String }

    private func toolRow(_ tool: ConnectedTool) -> some View {
        HStack(spacing: 12) {
            Image(tool.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                Text(tool.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                connectingTool = tool.id
            } label: {
                Text(connections.isConnected(tool.id) ? "Connected" : "Connect")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(connections.isConnected(tool.id) ? .green : .accentColor)
        }
    }

    private var webhookRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Webhook")
                Text("POST every call to your automation")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                connectingTool = "webhook"
            } label: {
                Text(connections.isConnected("webhook") ? "Connected" : "Connect")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(connections.isConnected("webhook") ? .green : .accentColor)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// Voice profiles management from Settings (count row in Defaults).
struct VoiceProfilesListView: View {
    @State private var profiles = VoiceProfileStore.load()
    @State private var showNew = false

    var body: some View {
        List {
            ForEach(profiles) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                    Text(profile.prompt)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .onDelete { offsets in
                profiles.remove(atOffsets: offsets)
                VoiceProfileStore.save(profiles)
            }
            Button("New Voice Profile…") { showNew = true }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Voice Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) {
            NewVoiceProfileView { profile in
                profiles.append(profile)
                VoiceProfileStore.save(profiles)
            }
        }
        .overlay {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No voice profiles",
                    systemImage: "waveform",
                    description: Text("Profiles are prompts that shape how any agent sounds.")
                )
            }
        }
    }
}

// Backend URL/secret form, moved out of the main settings list (§3.11).
struct BackendSettingsView: View {
    @AppStorage("backend.url") private var backendURL = ""

    var body: some View {
        Form {
            Section {
                TextField("Custom backend URL (optional)", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                Text(backendURL.isEmpty
                     ? "Using the built-in production backend (\(BackendConfig.production.host ?? "")). Enter a URL only to point the app at a development backend."
                     : "Overriding the built-in backend. Clear the field to go back to production.")
            }
        }
        .navigationTitle("Backend")
        .navigationBarTitleDisplayMode(.inline)
    }
}
