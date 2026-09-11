import SwiftUI
import UIKit

struct AgentCallsView: View {
    let agents: [Agent]

    @State private var status: RingAccessStatus?
    @State private var plaintextToken: String?
    @State private var selectedAgentId: UUID?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showRotateConfirmation = false

    private var selectedAgent: Agent? {
        let id = selectedAgentId ?? agents.first?.id
        return agents.first { $0.id == id }
    }

    var body: some View {
        List {
            Section {
                statusRow(
                    "Registered iPhones",
                    ready: (status?.deviceCount ?? 0) > 0,
                    detail: "\(status?.deviceCount ?? 0)"
                )
                statusRow(
                    "Push service",
                    ready: status?.apnsConfigured == true,
                    detail: status?.apnsConfigured == true ? "Configured" : "Needs APNs credentials"
                )
            } header: {
                Text("Incoming calls")
            } footer: {
                if !VoIPPushManager.isEnabled {
                    Text("This build has VoIP push disabled. Enable the Push Notifications capability and AgentlineVoIPPushEnabled after configuring the paid Apple team.")
                } else {
                    Text("Your agents ring through the system call screen, including when agentline is in the background.")
                }
            }

            Section {
                if let plaintextToken {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Copy this token now. It will not be shown again.")
                            .font(.footnote.weight(.semibold))
                        Text(plaintextToken)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy token", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = plaintextToken
                        }
                    }
                } else if let token = status?.token {
                    LabeledContent("Active token", value: token.prefix)
                    if let lastUsedAt = token.lastUsedAt {
                        LabeledContent("Last used", value: lastUsedAt.formatted(.relative(presentation: .named)))
                    }
                } else {
                    Text("Create a token for Claude Code, OpenClaw, n8n, or another automation.")
                        .foregroundStyle(.secondary)
                }

                Button(status?.token == nil ? "Create ring token" : "Rotate ring token") {
                    if status?.token == nil {
                        Task { await createToken() }
                    } else {
                        showRotateConfirmation = true
                    }
                }
                .disabled(busy)

                if status?.token != nil {
                    Button("Revoke token", role: .destructive) {
                        Task { await revokeToken() }
                    }
                    .disabled(busy)
                }
            } header: {
                Text("Automation access")
            } footer: {
                Text("The token can only ring agents in your account. Rotation immediately revokes the previous token.")
            }

            if let agent = selectedAgent {
                Section {
                    if agents.count > 1 {
                        Picker("Agent", selection: Binding(
                            get: { selectedAgentId ?? agents.first?.id },
                            set: { selectedAgentId = $0 }
                        )) {
                            ForEach(agents) { agent in
                                Text("\(agent.emoji) \(agent.name)").tag(Optional(agent.id))
                            }
                        }
                    }
                    Text(endpoint(for: agent))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy cURL example", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = curlExample(for: agent)
                    }
                } header: {
                    Text("Use it")
                } footer: {
                    Text("POST JSON with a brief and optional ISO-8601 deadline. A successful request returns 202 while APNs delivers the call.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Agents Call You")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            selectedAgentId = selectedAgentId ?? agents.first?.id
            VoIPPushManager.shared.start()
            VoIPPushManager.shared.syncStoredToken()
            await refresh()
        }
        .refreshable { await refresh() }
        .confirmationDialog(
            "Rotate the ring token?",
            isPresented: $showRotateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rotate token", role: .destructive) { Task { await createToken() } }
        } message: {
            Text("Automations using the current token will stop working immediately.")
        }
    }

    private func statusRow(_ title: String, ready: Bool, detail: String) -> some View {
        HStack {
            Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ready ? Color.primary : Color.orange)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        do {
            status = try await backend.ringAccessStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createToken() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        busy = true
        defer { busy = false }
        do {
            let created = try await backend.createRingToken()
            plaintextToken = created.token
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revokeToken() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        busy = true
        defer { busy = false }
        do {
            try await backend.revokeRingToken()
            plaintextToken = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func endpoint(for agent: Agent) -> String {
        BackendConfig.current.baseURL
            .appending(path: "/api/agents/\(agent.id.uuidString)/ring")
            .absoluteString
    }

    private func curlExample(for agent: Agent) -> String {
        let token = plaintextToken ?? "YOUR_RING_TOKEN"
        return """
        curl -X POST '\(endpoint(for: agent))' \\
          -H 'Authorization: Bearer \(token)' \\
          -H 'Content-Type: application/json' \\
          -d '{"brief":"The research is ready. Ask me which option to pursue."}'
        """
    }
}
