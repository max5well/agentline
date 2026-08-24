import SwiftUI

struct CallSummaryView: View {
    let record: CallRecord
    let agent: Agent

    @State private var checked: Set<String> = []
    @State private var transcript: [TranscriptEntry]
    @State private var feedback: CallFeedback?
    @State private var transcriptOpen = false
    @State private var editingTranscript = false
    @State private var ratingCall = false
    @State private var calendarItem: CalendarItem?
    @State private var reminderBusy = false
    @State private var reminderStatus: String?
    @State private var mcpConnected = false
    @State private var mcpBusy = false
    @State private var mcpStatus: String?
    @State private var driveBusy = false
    @State private var driveStatus: String?
    @AppStorage("handoff.includeTranscript") private var includeTranscript = false

    init(record: CallRecord, agent: Agent) {
        self.record = record
        self.agent = agent
        _transcript = State(initialValue: record.transcript)
        _feedback = State(initialValue: record.feedback)
    }

    var body: some View {
        List {
            Section {
                header.frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }

            if let objective = record.objective, !objective.isEmpty {
                Section("Objective") { Text(objective) }
            }

            Section("Summary") {
                Text(record.summary ?? "Summary is being written…")
                    .foregroundStyle(record.summary == nil ? .secondary : .primary)
            }

            if let intents = record.intents, !intents.isEmpty {
                Section {
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
                        .swipeActions {
                            Button("Calendar", systemImage: "calendar.badge.plus") {
                                calendarItem = CalendarItem(title: item)
                            }
                        }
                    }

                    Button {
                        Task { await addReminders(intents) }
                    } label: {
                        HStack {
                            Label(reminderStatus ?? "Add all to Reminders", systemImage: "checklist")
                            if reminderBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(reminderBusy)

                    Menu {
                        ForEach(intents, id: \.self) { item in
                            Button(item) { calendarItem = CalendarItem(title: item) }
                        }
                    } label: {
                        Label("Add to Calendar…", systemImage: "calendar.badge.plus")
                    }
                } header: {
                    Text("Action items")
                } footer: {
                    Text("Swipe an item to add just that action to Calendar.")
                }
            }

            Section {
                Toggle("Include transcript", isOn: $includeTranscript)

                ShareLink(item: shareText) {
                    Label("Share by email or message…", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: exportFile, preview: SharePreview(exportFile.filename)) {
                    Label("Share Markdown file…", systemImage: "doc.badge.arrow.up")
                }

                if ObsidianConnector.isConnected {
                    Button {
                        ObsidianConnector.save(record: record, agent: agent, includeTranscript: includeTranscript)
                    } label: { sendRow("Save to Obsidian", logo: "ObsidianLogo") }
                }
                if DriveConnector.isConnected {
                    Button { Task { await exportToDrive() } } label: {
                        HStack {
                            sendRow(driveStatus ?? "Export to Google Drive", logo: "DriveLogo")
                            if driveBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(driveBusy)
                }
                if mcpConnected {
                    Button { Task { await pushToMCP() } } label: {
                        HStack {
                            sendRow(mcpStatus ?? "Send via MCP", logo: "MCPLogo")
                            if mcpBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(mcpBusy)
                }
            } header: {
                Text("Share & export")
            } footer: {
                Text("Nothing leaves agentline until you choose a destination. Transcript sharing follows the toggle above.")
            }

            Section {
                Button {
                    ratingCall = true
                } label: {
                    Label(feedback == nil ? "Rate call quality" : "Update call rating", systemImage: "star.bubble")
                }
                if let feedback {
                    Text("Latency \(feedback.latency)/5 · Voice \(feedback.voice)/5 · Accuracy \(feedback.accuracy)/5 · Usefulness \(feedback.usefulness)/5")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Help improve agentline") }

            Section {
                DisclosureGroup("Full transcript", isExpanded: $transcriptOpen) {
                    if transcript.isEmpty {
                        Text("No transcript captured for this call.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(transcript.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.role == "user" ? "You" : agent.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.role == "user" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                            Text(entry.text).font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                    if !transcript.isEmpty {
                        Button("Correct transcript…", systemImage: "pencil") { editingTranscript = true }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Call Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task { mcpConnected = (try? await AppStore.backendIfConfigured()?.mcpStatus())??.toolName != nil }
        .sheet(isPresented: $editingTranscript) {
            TranscriptEditorView(transcript: transcript, agentName: agent.name) { updated in
                guard let backend = AppStore.backendIfConfigured() else { return }
                try await backend.updateCall(id: record.id, transcript: updated)
                transcript = updated
            }
        }
        .sheet(isPresented: $ratingCall) {
            QualityFeedbackView(initial: feedback) { updated in
                guard let backend = AppStore.backendIfConfigured() else { return }
                try await backend.updateCall(id: record.id, feedback: updated)
                feedback = updated
            }
        }
        .sheet(item: $calendarItem) { item in CalendarDraftSheet(title: item.title) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    private struct CalendarItem: Identifiable {
        let id = UUID()
        let title: String
    }

    private var header: some View {
        VStack(spacing: 10) {
            AgentAvatar(agent: agent, size: 62)
            Text(agent.name).font(.title3.weight(.semibold))
            Text(headerMeta).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var headerMeta: String {
        var parts = [record.startedAt.formatted(date: .abbreviated, time: .shortened), record.durationLabel]
        if let cents = record.costCents { parts.append(String(format: "€%.2f", Double(cents) / 100)) }
        return parts.joined(separator: " · ")
    }

    private func sendRow(_ title: String, logo: String) -> some View {
        HStack(spacing: 12) {
            Image(logo).resizable().scaledToFit().frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(title).foregroundStyle(Color.accentColor)
        }
    }

    private func addReminders(_ items: [String]) async {
        reminderBusy = true
        do {
            try await AppleActionExporter.addReminders(items)
            reminderStatus = "Added to Reminders ✓"
        } catch {
            reminderStatus = "Couldn’t add reminders"
        }
        reminderBusy = false
    }

    private func exportToDrive() async {
        driveBusy = true
        do {
            try await DriveConnector.export(record: record, agent: agent, includeTranscript: includeTranscript)
            driveStatus = "Exported ✓"
        } catch { driveStatus = "Failed — \(error.localizedDescription)" }
        driveBusy = false
    }

    private func pushToMCP() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        mcpBusy = true
        do {
            try await backend.mcpPush(callId: record.id)
            mcpStatus = "Sent ✓"
        } catch { mcpStatus = "Failed — \(error.localizedDescription)" }
        mcpBusy = false
    }

    private var exportFile: CallExportFile {
        CallExportFile(filename: "agentline-\(agent.name)-\(record.startedAt.formatted(.iso8601.year().month().day()))", markdown: shareText)
    }

    private var shareText: String {
        var lines = ["# Call with \(agent.name)", "", record.startedAt.formatted(date: .long, time: .shortened)]
        if let objective = record.objective, !objective.isEmpty { lines += ["", "## Objective", objective] }
        if let summary = record.summary { lines += ["", "## Summary", summary] }
        if let intents = record.intents, !intents.isEmpty {
            lines += ["", "## Action items"] + intents.map { "- [ ] \($0)" }
        }
        if includeTranscript && !transcript.isEmpty {
            lines += ["", "## Transcript"] + transcript.map { "**\($0.role == "user" ? "You" : agent.name):** \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }
}
