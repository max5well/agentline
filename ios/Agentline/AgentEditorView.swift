import SwiftUI

// Agent editor per design screen 08. Presented as a sheet from ContactsView,
// edits a copy and hands the result back on Save.
struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Bool
    @State private var draft: Agent
    private let isNew: Bool
    private let onSave: (Agent) -> Void

    init(agent: Agent?, onSave: @escaping (Agent) -> Void) {
        isNew = agent == nil
        _draft = State(initialValue: agent ?? Agent(
            id: UUID(), name: "", emoji: "🤖", persona: "",
            voice: VoiceOption.all[0].id, tier: .fast, memoryEnabled: true
        ))
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                navRow
                formLabel("Avatar")
                avatarField
                formLabel("Name")
                TextField("Agent name", text: $draft.name)
                    .focused($focusedField)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .fieldChrome()
                formLabel("Persona")
                TextField("Who is this agent? Role, background, scenario.", text: $draft.persona, axis: .vertical)
                    .focused($focusedField)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text.opacity(0.92))
                    .padding(14)
                    .frame(minHeight: 132, alignment: .topLeading)
                    .fieldChrome()
                formLabel("Language")
                languagePicker
                formLabel("Voice")
                voiceList
                formLabel("Voice style")
                TextField(
                    "Optional: delivery, e.g. slow and warm, slight British accent, dry humor",
                    text: Binding(get: { draft.voiceStyle ?? "" }, set: { draft.voiceStyle = $0 }),
                    axis: .vertical
                )
                .focused($focusedField)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(Theme.text.opacity(0.92))
                .padding(14)
                .frame(minHeight: 64, alignment: .topLeading)
                .fieldChrome()
                formLabel("Brain")
                brainPicker
                formLabel("Model")
                modelPicker
                formLabel("Memory")
                Toggle(isOn: $draft.memoryEnabled) {
                    Text("Remembers past calls")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 58)
                .glassCard()
                Text("After each call, a short summary is written automatically. With memory on, the last few summaries are given to \(draft.name.isEmpty ? "the agent" : draft.name) at the start of the next call — so conversations pick up where you left off. Nothing to manage; it just works per agent.")
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        // A focused field otherwise reserves keyboard space and the form
        // looks cut off — notorious in the simulator with the hardware
        // keyboard, where no keyboard is even visible.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = false }
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var navRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            }
            Spacer()
            Text(isNew ? "New Agent" : "Edit Agent")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            Button {
                onSave(draft)
                dismiss()
            } label: {
                Text("Save")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canSave ? Theme.accent : Theme.dim)
            }
            .disabled(!canSave)
            .frame(width: 48)
        }
        .padding(.bottom, 14)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var avatarField: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.7), Color(hex: 0x393228).opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                TextField("", text: $draft.emoji)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 29))
                    .onChange(of: draft.emoji) { _, new in
                        if new.count > 1 { draft.emoji = String(new.suffix(1)) }
                    }
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text("Emoji avatar")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                Text("Tap to change")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 102)
        .glassCard()
    }

    private static let languages = [
        "English", "German", "Spanish", "French", "Italian",
        "Portuguese", "Dutch", "Turkish", "Polish", "Japanese",
    ]

    private var languagePicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Spoken languages")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.text)
                Spacer()
                Menu {
                    ForEach(Self.languages, id: \.self) { lang in
                        Button {
                            toggleLanguage(lang)
                        } label: {
                            if draft.languages.contains(lang) {
                                Label(lang, systemImage: "checkmark")
                            } else {
                                Text(lang)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(draft.languages.joined(separator: ", "))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            Text("First language is the default; the agent switches when you do.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .glassCard()
    }

    private func toggleLanguage(_ lang: String) {
        var current = draft.languages
        if let idx = current.firstIndex(of: lang) {
            if current.count > 1 { current.remove(at: idx) } // keep at least one
        } else {
            current.append(lang)
        }
        draft.language = current.joined(separator: ", ")
    }

    // Options must stay within the tier's provider family (the backend
    // enforces this): big = OpenAI Realtime, local/fast = Gemini Live.
    private var modelOptions: [(id: String?, label: String)] {
        switch draft.tier {
        case .big:
            [(nil, "Auto (GPT Realtime)"),
             ("gpt-realtime", "GPT Realtime"),
             ("gpt-realtime-mini", "GPT Realtime Mini")]
        case .fast, .local:
            [(nil, "Auto (Gemini Flash)"),
             ("gemini-2.5-flash-native-audio-preview-12-2025", "Gemini 2.5 Flash Audio")]
        }
    }

    private var modelPicker: some View {
        HStack {
            Text("Voice model")
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
            Spacer()
            Menu {
                ForEach(modelOptions, id: \.label) { option in
                    Button {
                        draft.model = option.id
                    } label: {
                        if draft.model == option.id {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(modelOptions.first { $0.id == draft.model }?.label ?? draft.model ?? "Auto")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .glassCard()
    }

    private var voiceList: some View {
        VStack(spacing: 0) {
            ForEach(VoiceOption.all) { option in
                Button { draft.voice = option.id } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Text(option.blurb)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(draft.voice == option.id ? Theme.accent : Color.white.opacity(0.42), lineWidth: 1.5)
                                .background(Circle().fill(draft.voice == option.id ? Theme.accent : .clear))
                            if draft.voice == option.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(Color(hex: 0x140F08))
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 62)
                    .contentShape(Rectangle())
                }
                if option.id != VoiceOption.all.last?.id {
                    Divider().overlay(Color.white.opacity(0.075))
                }
            }
        }
        .glassCard()
    }

    private var brainPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Tier.allCases, id: \.self) { tier in
                    Button {
                        draft.tier = tier
                        // Model overrides are per provider family.
                        if !modelOptions.contains(where: { $0.id == draft.model }) {
                            draft.model = nil
                        }
                    } label: {
                        Text(tier.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(draft.tier == tier ? Color(hex: 0x130E08) : Theme.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                draft.tier == tier
                                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD9B16E), Color(hex: 0x8B6D3E)], startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))

            HStack(alignment: .top, spacing: 8) {
                ForEach(Tier.allCases, id: \.self) { tier in
                    Text(tier.blurb)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(7)
        .glassCard()
    }

    private func formLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(Theme.text.opacity(0.48))
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 7)
    }
}

struct VoiceOption: Identifiable {
    let id: String     // provider voice id
    let label: String
    let blurb: String

    // OpenAI Realtime ships fixed voices — these are the usable ones.
    // The *sound* isn't customizable, but speaking style can be steered
    // through the persona ("speak slowly", "dry humor", accents).
    static let all: [VoiceOption] = [
        .init(id: "marin", label: "Calm", blurb: "Warm, steady, reassuring"),
        .init(id: "cedar", label: "Bright", blurb: "Clear and energetic"),
        .init(id: "sage", label: "Gentle", blurb: "Soft-spoken and patient"),
        .init(id: "ash", label: "Deep", blurb: "Low, serious, deliberate"),
        .init(id: "coral", label: "Upbeat", blurb: "Friendly and lively"),
        .init(id: "verse", label: "Expressive", blurb: "Dynamic, animated delivery"),
    ]
}

extension Tier {
    var blurb: String {
        switch self {
        case .local: "Free, runs at home, casual chats"
        case .fast: "Quick and cheap, everyday topics"
        case .big: "Deepest reasoning, ~€0.20/min"
        }
    }
}

// Shared input-field chrome per the design's .field class.
private struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

private extension View {
    func fieldChrome() -> some View { modifier(FieldChrome()) }
}
