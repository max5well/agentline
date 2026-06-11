import SwiftUI

// Subscription & Billing (DESIGN-SPEC §3.12). Spend is aggregated
// client-side from call records until /api/usage exists (§6); the
// budget cap enforcement in the token route is also pending.
struct BillingView: View {
    @Bindable var store: AppStore
    @AppStorage("billing.monthlyBudgetCents") private var budgetCents = 1000

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text("This month")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(String(format: "€%.2f", Double(store.spentThisMonthCents) / 100))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(value: min(1, Double(store.spentThisMonthCents) / Double(max(budgetCents, 1))))
                        .tint(store.spentThisMonthCents >= budgetCents ? .red : .accentColor)
                    Text(String(format: "€%.2f monthly budget · calls pause politely at the cap", Double(budgetCents) / 100))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                HStack {
                    Text("Plan")
                    Spacer()
                    Text("Pay as you go")
                        .foregroundStyle(.secondary)
                }
                Picker("Monthly Budget", selection: $budgetCents) {
                    ForEach([500, 1000, 2000, 5000], id: \.self) { cents in
                        Text(String(format: "€%.0f", Double(cents) / 100)).tag(cents)
                    }
                }
                HStack {
                    Text("Payment Method")
                    Spacer()
                    Text("Coming soon")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(usageByAgent, id: \.agent.id) { usage in
                    HStack(spacing: 12) {
                        AgentAvatar(agent: usage.agent, size: 32)
                        Text(usage.agent.name)
                        Spacer()
                        Text(String(format: "€%.2f", Double(usage.cents) / 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Usage by agent")
            } footer: {
                Text("Local-tier calls are free and don't count toward the budget.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Subscription & Billing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var usageByAgent: [(agent: Agent, cents: Int)] {
        let calendar = Calendar.current
        let thisMonth = store.records.filter {
            calendar.isDate($0.startedAt, equalTo: .now, toGranularity: .month)
        }
        let byAgent = Dictionary(grouping: thisMonth, by: \.agentId)
        return byAgent
            .map { (agent: store.agent(for: $0.value[0]), cents: $0.value.compactMap(\.costCents).reduce(0, +)) }
            .filter { $0.cents > 0 }
            .sorted { $0.cents > $1.cents }
    }
}
