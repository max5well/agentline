import StoreKit
import SwiftUI

// Subscription & Billing (DESIGN-SPEC §3.12): server-metered usage,
// included minutes per class, prepaid PAYG credit. Plans and credit
// packs are Apple In-App Purchases (StoreKit 2); local testing runs on
// Agentline.storekit until App Store Connect products exist.
struct BillingView: View {
    @Bindable var store: AppStore
    @State private var usage: UsageReport?
    @State private var iap = StoreService()
    @State private var errorMessage: String?

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
                    Text("estimated provider cost")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            if let usage {
                Section {
                    quotaRow("Fast minutes", usage.fast)
                    quotaRow("Big-brain minutes", usage.big)
                } header: {
                    Text("Included minutes · \(usage.plan.capitalized) plan")
                } footer: {
                    Text("Beyond your included minutes, calls continue pay-as-you-go from your credit: €0.10/min fast, €0.40/min big-brain. Local calls are always free.")
                }

                Section {
                    ForEach(iap.plans, id: \.id) { product in
                        planRow(product, currentPlan: usage.plan)
                    }
                    Button("Restore Purchases") {
                        Task { await iap.restore(); await load() }
                    }
                    .font(.footnote)
                } header: {
                    Text("Plan")
                } footer: {
                    if iap.plans.isEmpty {
                        Text("Plans unavailable — the App Store didn't return products. On a dev build, run with the StoreKit configuration.")
                    }
                }

                Section {
                    HStack {
                        Text("Credit")
                        Spacer()
                        Text(String(format: "€%.2f", Double(usage.creditCents) / 100))
                            .monospacedDigit()
                            .foregroundStyle(usage.creditCents > 0 ? .primary : .secondary)
                    }
                    ForEach(iap.credits, id: \.id) { product in
                        creditRow(product)
                    }
                    if let message = errorMessage ?? iap.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Credit covers calls beyond your plan's included minutes and never expires.")
                }
            }

            Section {
                ForEach(usageByAgent, id: \.agent.id) { item in
                    HStack(spacing: 12) {
                        AgentAvatar(agent: item.agent, size: 32)
                        Text(item.agent.name)
                        Spacer()
                        Text(String(format: "%.0f min", item.minutes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Usage by agent")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Subscription & Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { await iap.start(); await load() }
        .refreshable { await load() }
    }

    private func planRow(_ product: Product, currentPlan: String) -> some View {
        let planId = product.id.components(separatedBy: ".").last ?? ""
        let isCurrent = planId == currentPlan
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.body.weight(.medium))
                Text(product.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task {
                        if await iap.purchase(product) { await load() }
                    }
                } label: {
                    if iap.purchasingId == product.id {
                        ProgressView()
                    } else {
                        Text("\(product.displayPrice)/mo")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private func creditRow(_ product: Product) -> some View {
        HStack {
            Text(product.displayName)
            Spacer()
            Button {
                Task {
                    if await iap.purchase(product) { await load() }
                }
            } label: {
                if iap.purchasingId == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private func quotaRow(_ title: String, _ classUsage: UsageReport.ClassUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(quotaLabel(classUsage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let quota = classUsage.quotaMinutes, quota > 0 {
                ProgressView(value: min(1, classUsage.usedMinutes / quota))
                    .tint(classUsage.usedMinutes >= quota ? .orange : .accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func quotaLabel(_ classUsage: UsageReport.ClassUsage) -> String {
        guard let quota = classUsage.quotaMinutes else {
            return String(format: "%.0f min · unlimited", classUsage.usedMinutes)
        }
        if quota == 0 { return "not included — uses credit" }
        return String(format: "%.0f of %.0f min", min(classUsage.usedMinutes, quota), quota)
    }

    private func load() async {
        guard let backend = AppStore.backendIfConfigured() else { return }
        usage = try? await backend.usage()
    }

    private var usageByAgent: [(agent: Agent, minutes: Double)] {
        let calendar = Calendar.current
        let thisMonth = store.records.filter {
            calendar.isDate($0.startedAt, equalTo: .now, toGranularity: .month)
        }
        return Dictionary(grouping: thisMonth, by: \.agentId)
            .map { (agent: store.agent(for: $0.value[0]), minutes: $0.value.compactMap(\.duration).reduce(0, +) / 60) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }
}
