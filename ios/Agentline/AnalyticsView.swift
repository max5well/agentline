import Charts
import SwiftUI

// Usage analytics (Max's request #9): minutes per agent, favorite
// model, call habits. Client-side over the fetched records (last 50
// calls — server-side aggregation comes with /api/usage).
struct AnalyticsView: View {
    @Bindable var store: AppStore

    var body: some View {
        List {
            Section {
                HStack {
                    stat(String(format: "%.0f", totalMinutes), "minutes")
                    Divider()
                    stat("\(store.records.count)", "calls")
                    Divider()
                    stat(String(format: "%.0f", averageMinutes), "min avg")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            if !minutesByAgent.isEmpty {
                Section("Minutes by agent") {
                    Chart(minutesByAgent, id: \.agent.id) { usage in
                        BarMark(
                            x: .value("Minutes", usage.minutes),
                            y: .value("Agent", usage.agent.name)
                        )
                        .foregroundStyle(usage.agent.avatarColor.gradient)
                        .annotation(position: .trailing) {
                            Text(String(format: "%.0f", usage.minutes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(minutesByAgent.count) * 44 + 20)
                    .padding(.vertical, 6)
                }
            }

            Section("Habits") {
                row("Favorite agent", favoriteAgent?.name ?? "—")
                row("Favorite model", favoriteModel ?? "—")
                row("Longest call", longestCall.map { "\($0.durationLabel) with \(store.agent(for: $0).name)" } ?? "—")
                row("Most active day", mostActiveDay ?? "—")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.bar",
                    description: Text("Analytics appear after your first calls.")
                )
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Aggregation

    private var totalMinutes: Double {
        store.records.compactMap(\.duration).reduce(0, +) / 60
    }

    private var averageMinutes: Double {
        let durations = store.records.compactMap(\.duration)
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count) / 60
    }

    private var minutesByAgent: [(agent: Agent, minutes: Double)] {
        Dictionary(grouping: store.records, by: \.agentId)
            .map { (agent: store.agent(for: $0.value[0]), minutes: $0.value.compactMap(\.duration).reduce(0, +) / 60) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }

    private var favoriteAgent: Agent? {
        minutesByAgent.first?.agent
    }

    private var favoriteModel: String? {
        let byModel = Dictionary(grouping: store.records) { store.agent(for: $0).modelDisplayName }
        return byModel
            .map { (name: $0.key, minutes: $0.value.compactMap(\.duration).reduce(0, +)) }
            .max { $0.minutes < $1.minutes }?
            .name
    }

    private var longestCall: CallRecord? {
        store.records.max { ($0.duration ?? 0) < ($1.duration ?? 0) }
    }

    private var mostActiveDay: String? {
        let byDay = Dictionary(grouping: store.records) {
            $0.startedAt.formatted(.dateTime.weekday(.wide))
        }
        return byDay.max { $0.value.count < $1.value.count }?.key
    }
}
