import Foundation

// Tool connection state shared by Settings and the call summary's
// "Send to" section. Connection is local-only until each integration
// gets a real OAuth/config flow.
struct ConnectedTool: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let icon: String      // SF Symbol stand-in; official brand assets are an open item (§8)
    let sendLabel: String

    var connected: Bool {
        get { UserDefaults.standard.bool(forKey: "tool.\(id).connected") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "tool.\(id).connected") }
    }
}

enum ConnectedToolsStore {
    static let all: [ConnectedTool] = [
        .init(id: "obsidian", name: "Obsidian", blurb: "Save summaries into a vault",
              icon: "square.stack.3d.up", sendLabel: "Save to Obsidian"),
        .init(id: "drive", name: "Google Drive", blurb: "Export transcripts as Docs or Markdown",
              icon: "externaldrive", sendLabel: "Export to Google Drive"),
        .init(id: "mcp", name: "MCP", blurb: "Send call data to custom tools",
              icon: "command", sendLabel: "Send via MCP"),
    ]

    static var connected: [ConnectedTool] {
        all.filter(\.connected)
    }
}
