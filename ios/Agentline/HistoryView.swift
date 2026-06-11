import SwiftUI

// Call history per design screen 09: search, date-grouped glass cards,
// rows push into CallSummaryView.
struct HistoryView: View {
    let records: [CallRecord]
    let agents: [Agent]

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                ForEach(groups, id: \.label) { group in
                    dateLabel(group.label)
                    VStack(spacing: 0) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record) {
                                HistoryRow(record: record, agent: agent(for: record))
                            }
                            if record.id != group.records.last?.id {
                                Divider().overlay(Color.white.opacity(0.075))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .glassCard()
                }
                if groups.isEmpty {
                    Text(query.isEmpty ? "No calls yet. They'll show up here after you hang up." : "No calls match “\(query)”.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .navigationTitle("Call History")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CallRecord.self) { record in
            CallSummaryView(record: record, agent: agent(for: record))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Search calls", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text)
        }
        .font(.system(size: 17))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(Color.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .padding(.bottom, 8)
    }

    private func dateLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .kerning(1.5)
            .foregroundStyle(Theme.text.opacity(0.48))
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func agent(for record: CallRecord) -> Agent {
        agents.first { $0.id == record.agentId }
            ?? Agent(id: record.agentId, name: "Unknown", emoji: "👤", persona: "", voice: "marin", tier: .fast, language: nil, memoryEnabled: false)
    }

    private var filtered: [CallRecord] {
        let sorted = records.sorted { $0.startedAt > $1.startedAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { record in
            let a = agent(for: record)
            return a.name.localizedCaseInsensitiveContains(query)
                || (record.summary?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var groups: [(label: String, records: [CallRecord])] {
        let calendar = Calendar.current
        var buckets: [(String, [CallRecord])] = []
        for record in filtered {
            let label: String
            if calendar.isDateInToday(record.startedAt) {
                label = "Today"
            } else if calendar.isDateInYesterday(record.startedAt) {
                label = "Yesterday"
            } else {
                label = "Earlier"
            }
            if let idx = buckets.firstIndex(where: { $0.0 == label }) {
                buckets[idx].1.append(record)
            } else {
                buckets.append((label, [record]))
            }
        }
        return buckets.map { (label: $0.0, records: $0.1) }
    }
}

struct HistoryRow: View {
    let record: CallRecord
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                Text(agent.emoji).font(.system(size: 26))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(agent.persona.components(separatedBy: ".").first ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let summary = record.summary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: 0x858681))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel)
                Text(record.durationLabel)
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(minHeight: 82)
        .contentShape(Rectangle())
    }

    private var timeLabel: String {
        if Calendar.current.isDateInToday(record.startedAt) {
            return record.startedAt.formatted(date: .omitted, time: .shortened)
        }
        return record.startedAt.formatted(.dateTime.weekday(.abbreviated))
    }
}
