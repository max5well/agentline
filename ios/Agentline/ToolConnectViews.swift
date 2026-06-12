import AuthenticationServices
import SwiftUI

// Connect flow for Obsidian: just the vault name — the export runs
// through the obsidian:// URL scheme, no account or server involved.
struct ObsidianConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vault = ObsidianConnector.vault
    let onChange: () -> Void

    private var obsidianInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "obsidian://")!)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !obsidianInstalled {
                    Section {
                        Label("Obsidian isn't installed on this iPhone", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Link("Get Obsidian from the App Store",
                             destination: URL(string: "https://apps.apple.com/app/obsidian-connected-notes/id1557175442")!)
                    }
                }
                Section {
                    TextField("Vault name", text: $vault)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("The vault name is shown at the bottom of Obsidian's sidebar (tap the vault switcher). It must match exactly, including spaces.")
                }

                Section {
                    Button {
                        sendTestNote()
                    } label: {
                        Label("Send test note", systemImage: "paperplane")
                    }
                    .disabled(vault.trimmingCharacters(in: .whitespaces).isEmpty || !obsidianInstalled)
                } footer: {
                    Text("Opens Obsidian and creates \"agentline test\" in the vault above. If Obsidian shows a vault error, the name doesn't match.")
                }
                if ObsidianConnector.isConnected {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            vault = ""
                            ObsidianConnector.vault = ""
                            onChange()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Connect Obsidian")
            .onAppear {
                // Saving the vault from the test flow shouldn't require Save.
                if vault.isEmpty { vault = ObsidianConnector.vault }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ObsidianConnector.vault = vault.trimmingCharacters(in: .whitespaces)
                        onChange()
                        dismiss()
                    }
                    .bold()
                    .disabled(vault.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension ObsidianConnectSheet {
    private func sendTestNote() {
        let trimmed = vault.trimmingCharacters(in: .whitespaces)
        ObsidianConnector.vault = trimmed
        onChange()
        var components = URLComponents(string: "obsidian://new")!
        components.queryItems = [
            URLQueryItem(name: "vault", value: trimmed),
            URLQueryItem(name: "name", value: "agentline test"),
            URLQueryItem(name: "content", value: "If you can read this, agentline is connected to this vault. You can delete this note."),
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

// Connect flow for MCP: server URL + token, backend validates by
// listing the tools, user picks the one that receives call digests.
struct MCPConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var tools: [MCPTool] = []
    @State private var serverName: String?
    @State private var selectedTool: String?
    @State private var busy = false
    @State private var errorMessage: String?
    let existing: MCPConnection?
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://my-server.example/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Auth token (optional)", text: $token)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("MCP server")
                } footer: {
                    Text("Any MCP server over Streamable HTTP. After every call, the summary, action items and transcript are sent to the tool you pick below.")
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        if busy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(tools.isEmpty ? "Connect & list tools" : "Reconnect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(url.isEmpty || busy)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !tools.isEmpty {
                    Section {
                        ForEach(tools) { tool in
                            Button {
                                selectedTool = tool.name
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.name).foregroundStyle(.primary)
                                        if let desc = tool.description {
                                            Text(desc).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if selectedTool == tool.name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Tool that receives calls\(serverName.map { " · \($0)" } ?? "")")
                    }
                }

                if existing?.toolName != nil {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                try? await AppStore.backendIfConfigured()?.mcpDisconnect()
                                onChange()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let selectedTool {
                                try? await AppStore.backendIfConfigured()?.mcpSelectTool(selectedTool)
                            }
                            onChange()
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(selectedTool == nil)
                }
            }
            .onAppear {
                if let existing {
                    url = existing.url
                    selectedTool = existing.toolName
                    serverName = existing.serverName
                }
            }
        }
    }

    private func connect() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        busy = true
        errorMessage = nil
        do {
            let result = try await backend.mcpConnect(url: url, authToken: token)
            tools = result.tools
            serverName = result.serverName
            if tools.isEmpty { errorMessage = "Connected, but the server exposes no tools." }
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }
}


// Google Drive connect: one-time OAuth client ID paste, then PKCE flow.
struct DriveConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webSession
    @State private var clientID = DriveConnector.clientID
    @State private var busy = false
    @State private var errorMessage: String?
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if DriveConnector.isConnected {
                    Section {
                        Label("Connected to Google Drive", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect", role: .destructive) {
                            DriveConnector.disconnect()
                            onChange()
                            dismiss()
                        }
                    } footer: {
                        Text("Call summaries can be exported as Markdown from every call summary's “Send to” section.")
                    }
                } else {
                    Section {
                        TextField("…apps.googleusercontent.com", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                    } header: {
                        Text("OAuth client ID")
                    } footer: {
                        Text("One-time setup: Google Cloud Console → APIs & Services → Credentials → Create OAuth client ID → type iOS → bundle ID dev.max5well.Agentline. Also enable the Google Drive API for the project. Paste the client ID here.")
                    }
                    Section {
                        Button {
                            Task { await connect() }
                        } label: {
                            if busy {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Connect Google Drive").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || !clientID.hasSuffix(".apps.googleusercontent.com"))
                        .listRowInsets(EdgeInsets())
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Sign-in runs through Google in a secure browser sheet. Tokens stay on this iPhone; agentline can only access files it creates.")
                    }
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DriveConnector.isConnected ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        busy = true
        errorMessage = nil
        DriveConnector.clientID = clientID.trimmingCharacters(in: .whitespaces)
        do {
            try await DriveConnector.connect(webSession: webSession)
            onChange()
            dismiss()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // user dismissed the sheet
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }
}

// Generic webhook: any URL receives the digest after every call.
struct WebhookConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var busy = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    let existing: String?
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://hooks.zapier.com/…", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Webhook URL")
                } footer: {
                    Text("After every call, this URL receives a JSON POST with the agent, summary, action items, and transcript. Works with Zapier, Make, n8n, or anything that accepts a webhook.")
                }
                Section {
                    Button {
                        Task { await saveAndTest() }
                    } label: {
                        if busy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Save & send test event").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || URL(string: url)?.scheme?.hasPrefix("http") != true)
                    .listRowInsets(EdgeInsets())
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .green)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                try? await AppStore.backendIfConfigured()?.setWebhook(url: nil)
                                onChange()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onChange()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { if url.isEmpty { url = existing ?? "" } }
        }
    }

    private func saveAndTest() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        busy = true
        statusMessage = nil
        do {
            try await backend.setWebhook(url: url.trimmingCharacters(in: .whitespaces))
            let status = try await backend.testWebhook()
            statusMessage = status ? "Test event delivered ✓" : "Saved, but the URL answered with an error."
            statusIsError = !status
            onChange()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        busy = false
    }
}
