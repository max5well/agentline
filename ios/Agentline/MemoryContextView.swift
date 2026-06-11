import SwiftUI

// Memory & Context per agent (DESIGN-SPEC §3.10). Stage 1: toggle +
// referenced conversations from real records. The editable memory file
// arrives with the backend's memoryFile column (§6).
struct MemoryContextView: View {
    @Binding var agent: Agent
    var records: [CallRecord] = []
    @State private var showAll = false
    @State private var editing = false
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                Toggle("Remember past calls", isOn: $agent.memoryEnabled)
            } footer: {
                Text("Before each call, the memory below is given to \(agent.name.isEmpty ? "the agent" : agent.name), so conversations pick up where you left off.")
            }

            if agent.memoryEnabled {
                Section {
                    if (agent.memoryFile ?? "").isEmpty && !editing {
                        Text("No memory yet — the file is written automatically after your next call.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        TextEditor(text: Binding(
                            get: { agent.memoryFile ?? "" },
                            set: { agent.memoryFile = $0; editing = true }
                        ))
                        .frame(minHeight: 140)
                        .font(.subheadline)
                    }
                } header: {
                    Text("Memory file")
                } footer: {
                    Text("Distilled automatically after every call and given to the agent when a call starts. Edits are saved with Done.")
                }

                if !records.isEmpty {
                    Section("Referenced conversations") {
                        ForEach(visibleRecords) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.summary?.components(separatedBy: ".").first ?? "Call")
                                    .lineLimit(1)
                                Text("\(record.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(record.durationLabel)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if records.count > 3 && !showAll {
                            Button("Show all \(records.count)") { showAll = true }
                        }
                    }
                }
            }

            if agent.memoryEnabled, !(agent.memoryFile ?? "").isEmpty {
                Section {
                    Button("Reset Memory", role: .destructive) { confirmReset = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .confirmationDialog("Reset memory?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Memory", role: .destructive) { agent.memoryFile = "" }
        } message: {
            Text("\(agent.name.isEmpty ? "The agent" : agent.name) forgets everything from past calls. Saved with Done.")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Memory & Context")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var visibleRecords: [CallRecord] {
        showAll ? records : Array(records.prefix(3))
    }
}