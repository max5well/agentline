import SwiftUI

// Agent editor (DESIGN-SPEC §3.5): Form sheet, avatar header, four
// Conversation disclosure rows into dedicated pickers.
struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Agent
    @State private var showAvatarPicker = false
    private let isNew: Bool
    private let records: [CallRecord]
    private let onSave: (Agent) -> Void

    init(agent: Agent?, records: [CallRecord] = [], onSave: @escaping (Agent) -> Void) {
        isNew = agent == nil
        _draft = State(initialValue: agent ?? Agent(
            id: UUID(), name: "", emoji: "", persona: "",
            voice: VoiceOption.all[0].id, tier: .fast, language: "English", memoryEnabled: true
        ))
        self.records = records
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        AgentAvatar(agent: draft, size: 64)
                        Button("Edit") { showAvatarPicker = true }
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Name & persona") {
                    TextField("Name", text: $draft.name)
                    TextField("Who is this agent? Role, background, scenario.",
                              text: $draft.persona, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Conversation") {
                    NavigationLink {
                        LanguagePickerView(selection: $draft.language)
                    } label: {
                        conversationRow("globe", "Language", draft.languages.joined(separator: ", "))
                    }
                    NavigationLink {
                        VoicePickerView(voice: $draft.voice, voiceStyle: $draft.voiceStyle)
                    } label: {
                        conversationRow("mic", "Voice", voiceLabel)
                    }
                    NavigationLink {
                        ModelPickerView(model: $draft.model, tier: $draft.tier)
                    } label: {
                        conversationRow("cpu", "Model", draft.modelDisplayName)
                    }
                    NavigationLink {
                        MemoryContextView(agent: $draft, records: records.filter { $0.agentId == draft.id })
                    } label: {
                        conversationRow("brain.head.profile", "Memory & Context", draft.memoryEnabled ? "On" : "Off")
                    }
                }
            }
            .navigationTitle(isNew ? "New Agent" : "Edit Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .bold()
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(agent: $draft)
            }
        }
    }

    private var voiceLabel: String {
        if let profile = VoiceProfileStore.load().first(where: { $0.id.uuidString == draft.voice }) {
            return profile.name
        }
        return VoiceOption.all.first { $0.id == draft.voice }?.label ?? draft.voice
    }

    private func conversationRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// VoiceOption lives in VoiceCatalog.swift (full per-provider catalogs).
