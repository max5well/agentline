import SwiftUI

// Agents is the action tab: tap a row to prepare a call; use the info button
// for setup. Global settings live in the toolbar, not a separate tab.
struct AgentsListView: View {
    @Bindable var store: AppStore
    @Binding var preparingCall: Agent?
    @Binding var editing: AgentEditTarget?
    @Binding var showTemplates: Bool
    @Binding var showSettings: Bool
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { agent in
                    AgentRow(
                        agent: agent,
                        onCall: { preparingCall = agent },
                        onEdit: { editing = AgentEditTarget(agent: agent) }
                    )
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search agents")
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Menu {
                        Button { showTemplates = true } label: {
                            Label("Choose Template…", systemImage: "person.2")
                        }
                        Button { editing = AgentEditTarget(agent: nil) } label: {
                            Label("New Agent", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Agent")
                }
            }
            .overlay {
                if filtered.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView {
                            Label("No agents yet", systemImage: "person.2")
                        } description: {
                            Text("Start from a template or build your own.")
                        } actions: {
                            Button("Choose Template") { showTemplates = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
    }

    private var filtered: [Agent] {
        guard !query.isEmpty else { return store.agents }
        return store.agents.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.persona.localizedCaseInsensitiveContains(query)
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    let onCall: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCall) {
                HStack(spacing: 12) {
                    AgentAvatar(agent: agent, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.body.weight(.semibold))
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.green, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call \(agent.name)")

            Button(action: onEdit) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(agent.name)")
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let role = agent.persona.components(separatedBy: ".").first ?? ""
        return [role, agent.modelDisplayName, agent.languages.first ?? "English"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
