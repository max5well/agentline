import SwiftUI

// Voice screen (DESIGN-SPEC §3.7): built-in provider voices + saved
// voice profiles + "New Voice Profile…".
struct VoicePickerView: View {
    @Binding var voice: String
    @Binding var voiceStyle: String?
    @State private var profiles = VoiceProfileStore.load()
    @State private var showNewProfile = false
    @State private var player = VoicePreviewPlayer()

    var body: some View {
        List {
            Section("Built-in voices") {
                ForEach(VoiceOption.all) { option in
                    voiceRow(id: option.id, name: option.label, detail: option.blurb,
                             previewVoice: option.id, previewStyle: nil) {
                        voice = option.id
                        voiceStyle = nil
                    }
                }
                if let message = player.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                ForEach(profiles) { profile in
                    voiceRow(
                        id: profile.id.uuidString,
                        name: profile.name,
                        detail: profile.createdAt.formatted(date: .abbreviated, time: .omitted),
                        previewVoice: profile.baseVoice, previewStyle: profile.prompt
                    ) {
                        // A profile rides on a built-in voice and adds its
                        // prompt as the delivery style.
                        voice = profile.baseVoice
                        voiceStyle = profile.prompt
                    }
                }
                .onDelete { offsets in
                    profiles.remove(atOffsets: offsets)
                    VoiceProfileStore.save(profiles)
                }
                Button("New Voice Profile…") { showNewProfile = true }
            } header: {
                Text("My voice profiles")
            } footer: {
                Text("Profiles are prompts that shape delivery — pace, accent, character. They're shared across all agents.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewProfile) {
            NewVoiceProfileView { profile in
                profiles.append(profile)
                VoiceProfileStore.save(profiles)
            }
        }
    }

    private func voiceRow(id: String, name: String, detail: String,
                          previewVoice: String, previewStyle: String?,
                          select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Button {
                    Task { await player.play(id: id, voice: previewVoice, style: previewStyle) }
                } label: {
                    if player.loadingId == id {
                        ProgressView().frame(width: 24)
                    } else {
                        Image(systemName: player.playingId == id ? "stop.circle.fill" : "play.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected(id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func isSelected(_ id: String) -> Bool {
        if let profile = profiles.first(where: { $0.id.uuidString == id }) {
            return voice == profile.baseVoice && voiceStyle == profile.prompt
        }
        return voice == id && (voiceStyle ?? "").isEmpty
    }
}

// New voice profile (DESIGN-SPEC §3.8). Preview generation needs a TTS
// endpoint — until it exists, Save enables once the description is set.
struct NewVoiceProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var prompt = ""
    @State private var previewed = false
    @State private var player = VoicePreviewPlayer()
    let onSave: (VoiceProfile) -> Void

    private static let suggestions = ["calm narrator", "energetic coach", "posh butler"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $name)
                }
                Section {
                    TextField("Describe the voice — pace, accent, character…",
                              text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { prompt = suggestion }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .font(.footnote)
                            }
                        }
                    }
                } header: {
                    Text("Describe the voice")
                } footer: {
                    Text("The prompt is stored, so the voice can be re-rendered on any provider.")
                }

                Section {
                    Button {
                        Task {
                            await player.play(id: "draft", voice: "marin", style: prompt)
                            if player.errorMessage == nil { previewed = true }
                        }
                    } label: {
                        if player.loadingId != nil {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(previewed ? "Play Preview Again" : "Generate Preview")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowInsets(EdgeInsets())
                    if let message = player.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(previewed ? "This is how the profile sounds on the default voice." : "Generate a preview to hear the prompt before saving.")
                }
            }
            .navigationTitle("New Voice Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(VoiceProfile(id: UUID(), name: displayName, prompt: prompt, baseVoice: "marin", createdAt: .now))
                        dismiss()
                    }
                    .bold()
                    .disabled(!previewed || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(prompt.prefix(24)) : trimmed
    }
}

struct VoiceProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var prompt: String
    var baseVoice: String
    let createdAt: Date
}

// Local persistence until the /api/voice-profiles CRUD exists (§6).
enum VoiceProfileStore {
    private static let key = "voiceProfiles"

    static func load() -> [VoiceProfile] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([VoiceProfile].self, from: data)) ?? []
    }

    static func save(_ profiles: [VoiceProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
