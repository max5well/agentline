import SwiftUI

// Avatar picker (DESIGN-SPEC §5), stage 1: emoji + monogram are pure
// data. Photo and generated avatars need the storage bucket + image-gen
// endpoint and ship in stage 2.
struct AvatarPickerView: View {
    @Binding var agent: Agent
    @Environment(\.dismiss) private var dismiss

    private static let suggestedEmoji = [
        "📜", "🌱", "🗣️", "🧠", "🎓", "💼", "🧭", "🎨",
        "⚖️", "🔬", "🏛️", "💪", "🍳", "🎹", "✈️", "📈",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AgentAvatar(agent: agent, size: 96)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Emoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Self.suggestedEmoji, id: \.self) { emoji in
                            Button {
                                agent.emoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        agent.emoji == emoji ? Color.accentColor.opacity(0.2) : .clear,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        agent.emoji = ""
                    } label: {
                        HStack {
                            Text("Monogram (\(agent.monogram))")
                                .foregroundStyle(.primary)
                            Spacer()
                            if agent.emoji.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                } footer: {
                    Text("Initials on the agent's color — the default for new agents.")
                }

                Section {
                    disabledRow("Take Photo or Choose Image", icon: "camera")
                    disabledRow("Generate Avatar", icon: "sparkles")
                } footer: {
                    Text("Photos and generated avatars are coming with avatar storage on the backend.")
                }
            }
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    private func disabledRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("Soon")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
    }
}
