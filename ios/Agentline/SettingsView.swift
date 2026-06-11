import SwiftUI

// Settings per design screen 11: connected handoff tools + default
// handoff toggles. Connection state is local-only until handoff lands.
struct SettingsView: View {
    @AppStorage("handoff.askAfterCall") private var askAfterCall = true
    @AppStorage("handoff.includeTranscript") private var includeTranscript = false
    @AppStorage("backend.url") private var backendURL = ""
    @State private var auth = AuthStore.shared
    @State private var tools = HandoffTool.all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Backend")
                Text(connectionBlurb)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(BackendConfig.current.isConfigured && auth.session != nil ? Color(hex: 0x93D7AA) : Theme.danger)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                TextField("Backend URL", text: $backendURL, prompt: Text("https://agentline-chi.vercel.app"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .glassCard()

                if let session = auth.session {
                    sectionLabel("Account")
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.email ?? "Signed in")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Text("Agents and call history belong to this account.")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Sign out") { auth.signOut() }
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.danger)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    .glassCard()
                }

                sectionLabel("Connected tools")
                Text("Connect destinations that can receive call summaries and transcripts after each call.")
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 18)

                VStack(spacing: 0) {
                    ForEach($tools) { $tool in
                        toolRow($tool)
                        if tool.id != tools.last?.id {
                            Divider().overlay(Color.white.opacity(0.075))
                        }
                    }
                }
                .glassCard()

                sectionLabel("Default handoff")
                toggleRow("Ask after every call", isOn: $askAfterCall)
                toggleRow("Include full transcript", isOn: $includeTranscript)
                    .padding(.top, 10)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var connectionBlurb: String {
        if !BackendConfig.current.isConfigured {
            return "Not configured — calls run in demo mode with a scripted agent and no audio."
        }
        return auth.session != nil
            ? "Connected — calls use the real voice provider."
            : "Signed out — sign in to load your agents and place calls."
    }

    private func toolRow(_ tool: Binding<HandoffTool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.wrappedValue.icon)
                .font(.system(size: 21))
                .foregroundStyle(Color(hex: 0xE9C887))
                .frame(width: 46, height: 46)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.wrappedValue.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(tool.wrappedValue.blurb)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Button {
                tool.wrappedValue.connected.toggle()
            } label: {
                Text(tool.wrappedValue.connected ? "Connected" : "Connect")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tool.wrappedValue.connected ? Color(hex: 0x93D7AA) : Color(hex: 0xEBC98B))
                    .frame(width: 94, height: 36)
                    .background(
                        (tool.wrappedValue.connected ? Theme.green : Theme.accent).opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke((tool.wrappedValue.connected ? Theme.green : Theme.accent).opacity(0.38), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 82)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .glassCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(1.5)
            .foregroundStyle(Theme.text.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.top, 22)
            .padding(.bottom, 10)
    }
}

struct HandoffTool: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let icon: String
    var connected: Bool

    static let all: [HandoffTool] = [
        .init(id: "obsidian", name: "Obsidian", blurb: "Save summaries into a vault", icon: "square.grid.2x2", connected: true),
        .init(id: "drive", name: "Google Drive", blurb: "Export transcripts as Docs or Markdown", icon: "externaldrive", connected: false),
        .init(id: "mcp", name: "MCP", blurb: "Send call data to custom tools", icon: "command", connected: false),
        .init(id: "hermes", name: "Hermes", blurb: "Share summaries to your assistant", icon: "sparkle", connected: true),
    ]
}
