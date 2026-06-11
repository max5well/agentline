import SwiftUI

// Call summary (DESIGN-SPEC §3.4): centered header, Summary / Action
// items / Send to sections, share toolbar button.
struct CallSummaryView: View {
    let record: CallRecord
    let agent: Agent

    @State private var checked: Set<String> = []
    @State private var transcriptOpen = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Summary") {
                Text(record.summary ?? "Summary is being written…")
                    .font(.body)
                    .foregroundStyle(record.summary == nil ? .secondary : .primary)
            }

            if let intents = record.intents, !intents.isEmpty {
                Section("Action items") {
                    ForEach(intents, id: \.self) { item in
                        Button {
                            if checked.contains(item) { checked.remove(item) } else { checked.insert(item) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checked.contains(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(item) ? Color.accentColor : Color.secondary)
                                Text(item)
                                    .strikethrough(checked.contains(item))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(ConnectedToolsStore.connected) { tool in
                    Button {} label: {
                        Label(tool.sendLabel, systemImage: tool.icon)
                    }
                }
                ShareLink(item: shareText) {
                    Label("Share transcript…", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Send to")
            } footer: {
                Text("Connected tools are managed in Settings.")
            }

            Section {
                DisclosureGroup("Full transcript", isExpanded: $transcriptOpen) {
                    if record.transcript.isEmpty {
                        Text("No transcript captured for this call.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(record.transcript.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.role == "user" ? "You" : agent.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.role == "user" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                            Text(entry.text)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Call Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AgentAvatar(agent: agent, size: 62)
            Text(agent.name)
                .font(.title3.weight(.semibold))
            Text(headerMeta)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var headerMeta: String {
        var parts = [record.startedAt.formatted(date: .abbreviated, time: .shortened), record.durationLabel]
        if let cents = record.costCents {
            parts.append(String(format: "€%.2f", Double(cents) / 100))
        }
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        var lines = ["Call with \(agent.name) — \(record.startedAt.formatted(date: .abbreviated, time: .shortened))"]
        if let summary = record.summary { lines.append("\nSummary:\n\(summary)") }
        if !record.transcript.isEmpty {
            lines.append("\nTranscript:")
            lines.append(contentsOf: record.transcript.map { "\($0.role == "user" ? "You" : agent.name): \($0.text)" })
        }
        return lines.joined(separator: "\n")
    }
}
