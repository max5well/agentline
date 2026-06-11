import SwiftUI

// Tool connections (Max's #6). Obsidian is fully local (vault name +
// URL scheme), MCP lives on the backend (server URL + chosen tool),
// Google Drive waits for its OAuth client.
struct ConnectedTool: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let logo: String      // asset catalog image
    let sendLabel: String
}

enum ConnectedToolsStore {
    static let all: [ConnectedTool] = [
        .init(id: "obsidian", name: "Obsidian", blurb: "Save summaries into your vault",
              logo: "ObsidianLogo", sendLabel: "Save to Obsidian"),
        .init(id: "drive", name: "Google Drive", blurb: "Export transcripts as Docs",
              logo: "DriveLogo", sendLabel: "Export to Google Drive"),
        .init(id: "mcp", name: "MCP", blurb: "Send call data to your own tools",
              logo: "MCPLogo", sendLabel: "Send via MCP"),
    ]
}

// MARK: - Obsidian (local: vault name + obsidian:// URL scheme)

enum ObsidianConnector {
    @MainActor static var vault: String {
        get { UserDefaults.standard.string(forKey: "tool.obsidian.vault") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tool.obsidian.vault") }
    }

    @MainActor static var isConnected: Bool { !vault.isEmpty }

    @MainActor
    static func save(record: CallRecord, agent: Agent, includeTranscript: Bool) {
        var md = "## Call with \(agent.name)\n\n"
        md += "_\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationLabel)_\n\n"
        if let summary = record.summary { md += "### Summary\n\(summary)\n\n" }
        if let intents = record.intents, !intents.isEmpty {
            md += "### Action items\n" + intents.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if includeTranscript, !record.transcript.isEmpty {
            md += "### Transcript\n"
            md += record.transcript.map { "**\($0.role == "user" ? "Max" : agent.name):** \($0.text)" }.joined(separator: "\n")
        }
        // obsidian://new opens the app and creates the note. URLs have
        // practical length limits — clamp the body.
        let title = "Call with \(agent.name) \(record.startedAt.formatted(.dateTime.year().month().day().hour().minute()))"
        var components = URLComponents(string: "obsidian://new")!
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "name", value: title),
            URLQueryItem(name: "content", value: String(md.prefix(8000))),
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Connection state shown in Settings / summary

@MainActor
@Observable
final class ToolConnections {
    var obsidianConnected = ObsidianConnector.isConnected
    var mcpConnection: MCPConnection?
    var loaded = false

    func refresh() async {
        obsidianConnected = ObsidianConnector.isConnected
        if let backend = AppStore.backendIfConfigured() {
            mcpConnection = try? await backend.mcpStatus()
        }
        loaded = true
    }

    var mcpConnected: Bool { mcpConnection?.toolName != nil }

    func isConnected(_ toolId: String) -> Bool {
        switch toolId {
        case "obsidian": obsidianConnected
        case "mcp": mcpConnected
        default: false
        }
    }
}

struct MCPConnection: Codable {
    let url: String
    let toolName: String?
    let serverName: String?

    enum CodingKeys: String, CodingKey {
        case url
        case toolName = "tool_name"
        case serverName = "server_name"
    }
}

struct MCPTool: Codable, Identifiable {
    let name: String
    let description: String?
    var id: String { name }
}
