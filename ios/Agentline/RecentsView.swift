import SwiftUI

struct RecentsView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var selectedAgentId: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record) {
                                RecentRow(record: record, agent: store.agent(for: record))
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { group.records[$0] })
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search calls and transcripts")
            .navigationTitle("Calls")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            selectedAgentId = nil
                        } label: {
                            if selectedAgentId == nil { Label("All Agents", systemImage: "checkmark") }
                            else { Text("All Agents") }
                        }
                        Divider()
                        ForEach(store.agents) { agent in
                            Button {
                                selectedAgentId = agent.id
                            } label: {
                                if selectedAgentId == agent.id { Label(agent.name, systemImage: "checkmark") }
                                else { Text(agent.name) }
                            }
                        }
                    } label: {
                        Label(agentFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Filter calls by agent")
                }
            }
            .navigationDestination(for: CallRecord.self) { record in
                CallSummaryView(record: record, agent: store.agent(for: record))
            }
            .overlay {
                if store.records.isEmpty {
                    ContentUnavailableView(
                        "No calls yet",
                        systemImage: "clock",
                        description: Text("Calls show up here after you hang up.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No matching calls",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another agent or search term.")
                    )
                }
            }
        }
    }

    private var agentFilterLabel: String {
        guard let selectedAgentId else { return "All Agents" }
        return store.agents.first { $0.id == selectedAgentId }?.name ?? "Agent"
    }

    private func delete(_ records: [CallRecord]) {
        store.records.removeAll { record in records.contains { $0.id == record.id } }
        if let backend = AppStore.backendIfConfigured() {
            Task { for record in records { try? await backend.deleteCall(id: record.id) } }
        }
    }

    private var filtered: [CallRecord] {
        store.records.filter { record in
            let matchesAgent = selectedAgentId == nil || record.agentId == selectedAgentId
            let matchesQuery = query.isEmpty
                || store.agent(for: record).name.localizedCaseInsensitiveContains(query)
                || (record.summary?.localizedCaseInsensitiveContains(query) ?? false)
                || (record.intents ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
                || record.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
            return matchesAgent && matchesQuery
        }
    }

    private var groups: [(label: String, records: [CallRecord])] {
        let calendar = Calendar.current
        let sorted = filtered.sorted { $0.startedAt > $1.startedAt }
        var buckets: [(String, [CallRecord])] = []
        for record in sorted {
            let label: String
            if calendar.isDateInToday(record.startedAt) { label = "Today" }
            else if calendar.isDateInYesterday(record.startedAt) { label = "Yesterday" }
            else { label = record.startedAt.formatted(date: .abbreviated, time: .omitted) }
            if let idx = buckets.firstIndex(where: { $0.0 == label }) { buckets[idx].1.append(record) }
            else { buckets.append((label, [record])) }
        }
        return buckets.map { (label: $0.0, records: $0.1) }
    }
}

struct RecentRow: View {
    let record: CallRecord
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(agent: agent, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let topic = record.summary?.components(separatedBy: ".").first ?? "No summary"
        return "\(topic) · \(record.durationLabel)"
    }
}
