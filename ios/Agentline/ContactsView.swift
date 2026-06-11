import SwiftUI

struct ContactsView: View {
    @State private var agents: [Agent] = Agent.samples
    @State private var activeCall: Agent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AGENTS")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.4)
                        .foregroundStyle(Theme.text.opacity(0.5))
                        .padding(.horizontal, 8)

                    VStack(spacing: 0) {
                        ForEach(agents) { agent in
                            Button { activeCall = agent } label: {
                                ContactRow(agent: agent)
                            }
                            if agent.id != agents.last?.id {
                                Divider().overlay(Color.white.opacity(0.075))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassCard()
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("agentline")
            .fullScreenCover(item: $activeCall) { agent in
                CallView(agent: agent, session: MockVoiceSession())
            }
            .onAppear {
                // UI-test hook: launch directly into a mock call.
                if ProcessInfo.processInfo.arguments.contains("-autocall") {
                    activeCall = agents.first
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

struct ContactRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Text(agent.emoji).font(.system(size: 26))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(agent.persona.components(separatedBy: ".").first ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(agent.tier.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
                )
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }
}

extension Agent {
    static let samples: [Agent] = [
        .init(id: UUID(), name: "Maya", emoji: "📜", persona: "Modern history tutor. Socratic, opinionated, concrete.", voice: "marin", tier: .big, memoryEnabled: true),
        .init(id: UUID(), name: "Marco", emoji: "🌱", persona: "Startup sparring partner. Challenges every assumption.", voice: "cedar", tier: .fast, memoryEnabled: true),
        .init(id: UUID(), name: "Elena", emoji: "🗣️", persona: "Spanish coach. Conversational immersion, gentle corrections.", voice: "marin", tier: .fast, memoryEnabled: true),
    ]
}
