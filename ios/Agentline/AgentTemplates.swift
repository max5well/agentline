import SwiftUI

// Curated starting points — fixes the blank-persona cold start. One tap
// adds the agent; everything stays editable afterwards.
struct AgentTemplate: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let persona: String
    let voice: String
    let tier: Tier
    let language: String

    // Pre-generated portraits hosted in the public avatars bucket
    // (avatars/templates/<id>.jpg) so the gallery and the created agent
    // share one image — no per-user generation cost.
    var avatarUrl: String {
        "https://hwlkjbgidezoompnrkcu.supabase.co/storage/v1/object/public/avatars/templates/\(id).jpg"
    }

    var agent: Agent {
        Agent(id: UUID(), name: name, emoji: emoji, persona: persona,
              voice: voice, tier: tier, language: language,
              avatarUrl: avatarUrl, memoryEnabled: true)
    }

    static let all: [AgentTemplate] = [
        .init(id: "news", name: "Vera", emoji: "🗞️",
              persona: "News reporter. Briefs you on today's top stories like a sharp morning-radio anchor: headlines first, then detail on whatever you ask about. Uses web search to look up current news and always says when something is opinion rather than reporting.",
              voice: "marin", tier: .fast, language: "English"),
        .init(id: "startup", name: "Marco", emoji: "🌱",
              persona: "Startup advisor. Challenges every assumption, plays devil's advocate, pushes for concrete next steps before the call ends.",
              voice: "cedar", tier: .fast, language: "English"),
        .init(id: "history", name: "Maya", emoji: "📜",
              persona: "Modern history teacher. Socratic, opinionated, concrete. Challenges assumptions with primary sources and keeps lessons conversational.",
              voice: "marin", tier: .big, language: "English"),
        .init(id: "reflect", name: "Sam", emoji: "🧘",
              persona: "Thoughtful reflection partner. Asks open questions about your day, helps untangle decisions and feelings. Never gives unsolicited advice, mostly listens.",
              voice: "sage", tier: .fast, language: "English"),
        .init(id: "spanish", name: "Elena", emoji: "🗣️",
              persona: "Spanish coach. Conversational immersion with gentle corrections. Adapts difficulty to the learner and recaps mistakes at the end.",
              voice: "marin", tier: .fast, language: "Spanish"),
        .init(id: "stories", name: "Pip", emoji: "🦊",
              persona: "Children's storyteller. Spins gentle, imaginative bedtime stories and lets the listener steer the plot. Always kind, never scary.",
              voice: "coral", tier: .fast, language: "English"),
        .init(id: "interview", name: "Nora", emoji: "💼",
              persona: "Tough but fair interview coach. Runs realistic job interviews for the role you name, then gives blunt, specific feedback on your answers.",
              voice: "ash", tier: .big, language: "English"),
    ]
}

struct TemplateGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Agent) -> Void
    @State private var added: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AgentTemplate.all) { template in
                        HStack(spacing: 12) {
                            AgentAvatar(agent: template.agent, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.body.weight(.semibold))
                                Text(template.persona.components(separatedBy: ".").first ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button(added.contains(template.id) ? "Added" : "Add") {
                                onAdd(template.agent)
                                added.insert(template.id)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(added.contains(template.id) ? .green : .accentColor)
                            .disabled(added.contains(template.id))
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Templates are starting points — tap any agent later to change its persona, voice, model, or language.")
                }
            }
            .navigationTitle("Agent Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }
}

// Three-page first-run explainer.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let onChooseTemplates: () -> Void

    var body: some View {
        TabView {
            page(icon: "phone.fill", color: .green, title: "Call your agents",
                 text: "agentline is a contact book of AI agents you design — a tutor, a coach, a sparring partner. Tap the green button and talk, like a normal phone call.")
            page(icon: "brain.head.profile", color: .purple, title: "They remember",
                 text: "After every call you get a summary and action items. Agents keep a memory file, so the next call picks up where you left off.")
            VStack(spacing: 24) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("Start with a template")
                    .font(.title2.weight(.bold))
                Text("Pick a ready-made agent and customize it later — or build your own from scratch.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    dismiss()
                    onChooseTemplates()
                } label: {
                    Text("Choose templates")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Skip") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }

    private func page(icon: String, color: Color, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(color)
            Text(title)
                .font(.title2.weight(.bold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Swipe to continue")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .padding(.bottom, 40)
    }
}
