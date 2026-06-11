import SwiftUI

// Memory & Context per agent (DESIGN-SPEC §3.10). Stage 1: toggle +
// referenced conversations from real records. The editable memory file
// arrives with the backend's memoryFile column (§6).
struct MemoryContextView: View {
    @Binding var agent: Agent
    var records: [CallRecord] = []
    @State private var showAll = false

    var body: some View {
        List {
            Section {
                Toggle("Remember past calls", isOn: $agent.memoryEnabled)
            } footer: {
                Text("Before each call, the memory below is given to \(agent.name.isEmpty ? "the agent" : agent.name), so conversations pick up where you left off.")
            }

            if agent.memoryEnabled {
                Section {
                    Text("The memory file is distilled automatically after every call. Editing it in the app is coming with the next backend update.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Memory file")
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Memory & Context")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var visibleRecords: [CallRecord] {
        showAll ? records : Array(records.prefix(3))
    }
}