import SwiftUI

struct PreparedCall: Identifiable {
    let id = UUID()
    let agent: Agent
    let objective: String?
}

struct CallPreparationView: View {
    let agent: Agent
    let lastCall: CallRecord?
    let onStart: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var objective = ""
    @State private var usage: UsageReport?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        AgentAvatar(agent: agent, size: 68)
                        Text(agent.name)
                            .font(.title3.weight(.semibold))
                        Text(agent.modelDisplayName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                if let summary = lastCall?.summary, !summary.isEmpty {
                    Section("Pick up where you left off") {
                        Button {
                            objective = "Continue our last conversation: \(summary)"
                        } label: {
                            Label("Continue our last conversation", systemImage: "arrow.uturn.forward.circle.fill")
                        }
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Section {
                    TextField("What do you want to achieve?", text: $objective, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Call objective")
                } footer: {
                    Text("Optional. A clear objective helps the agent guide the call and close with useful next steps.")
                }

                Section("Before you call") {
                    LabeledContent("Model", value: agent.modelDisplayName)
                    LabeledContent("Estimated rate", value: estimatedRate)
                    if agent.tier == .big {
                        Label("Smart calls use your Big-brain allowance or credit.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let usage {
                        LabeledContent("Plan", value: usage.plan.capitalized)
                        LabeledContent("Credit", value: String(format: "€%.2f", Double(usage.creditCents) / 100))
                    }
                }

                Section {
                    Button {
                        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
                        onStart(trimmed.isEmpty ? nil : trimmed)
                    } label: {
                        Label("Start call", systemImage: "phone.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ready to call?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                usage = try? await AppStore.backendIfConfigured()?.usage()
            }
        }
    }

    private var estimatedRate: String {
        switch agent.tier {
        case .local: "Free when local is available"
        case .fast: "about €0.10/min"
        case .big: "about €0.40/min"
        }
    }
}
