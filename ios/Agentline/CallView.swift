import SwiftUI

struct CallView: View {
    let agent: Agent
    let session: any VoiceSession

    @Environment(\.dismiss) private var dismiss
    @State private var state: VoiceSessionState = .connecting
    @State private var transcript: [TranscriptEntry] = []
    @State private var costCents = 0
    @State private var startedAt = Date.now
    @State private var muted = false
    @State private var captionsOn = true
    @State private var errorMessage: String?
    @State private var partialCaption: String?
    @State private var showTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            Orb(state: state)
            Spacer()
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 18)
            }
            captionArea
            controls
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task {
            for await event in session.events {
                switch event {
                case .state(let s):
                    state = s
                    // On error, stay on screen so the message is readable;
                    // the user leaves via the hang-up button.
                    if s == .ended && errorMessage == nil { await endAndDismiss() }
                case .transcript(let entry):
                    transcript.append(entry)
                    if entry.role == "agent" { partialCaption = nil }
                case .partialTranscript(let text):
                    partialCaption = text
                case .costTick(let cents): costCents = cents
                case .error(let message): errorMessage = message
                }
            }
        }
        .task { try? await session.start(agent: agent) }
        .sheet(isPresented: $showTranscript) {
            LiveTranscriptPanel(agentName: agent.name, transcript: transcript, partial: partialCaption)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(hex: 0x111315))
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text(agent.name)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.text)
            Text(stateLabel)
                .font(.subheadline)
                .foregroundStyle(state == .agentSpeaking ? Theme.accent : Theme.muted)
            HStack(spacing: 8) {
                Text(startedAt, style: .timer)
                Text("·")
                Text(String(format: "%.2f €", Double(costCents) / 100))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(Theme.dim)
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle, .connecting: "Connecting"
        case .listening: "Listening"
        case .agentSpeaking: "Speaking"
        case .thinking: "Thinking"
        case .reconnecting: "Reconnecting"
        case .ended: "Ended"
        }
    }

    // Fixed-height so the controls don't jump when captions come and go.
    private var captionArea: some View {
        Group {
            if captionsOn, let caption = partialCaption ?? lastAgentLine {
                Text(caption)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text.opacity(0.92))
                    .lineLimit(3, reservesSpace: false)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 36)
                    .animation(nil, value: caption)
            }
        }
        .frame(height: 70)
        .padding(.bottom, 14)
    }

    private var lastAgentLine: String? {
        guard state == .agentSpeaking else { return nil }
        return transcript.last(where: { $0.role == "agent" })?.text
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                ControlButton(icon: muted ? "mic.slash.fill" : "mic.fill", label: "mute", active: muted) {
                    muted.toggle()
                    session.setMuted(muted)
                }
                ControlButton(icon: "speaker.wave.2.fill", label: "audio", active: false) {}
                ControlButton(icon: "captions.bubble.fill", label: "captions", active: captionsOn) {
                    captionsOn.toggle()
                }
                ControlButton(icon: "list.bullet.rectangle.fill", label: "transcript", active: showTranscript) {
                    showTranscript = true
                }
            }
            Button {
                Task { await endAndDismiss() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.danger, in: Circle())
            }
        }
        .padding(.bottom, 10)
    }

    private func endAndDismiss() async {
        await session.end()
        // ADR-4: transcript is buffered live and POSTed on hangup; the
        // backend's summary worker fills in the rest.
        let config = BackendConfig.current
        if config.isConfigured, !(session is MockVoiceSession) {
            try? await BackendClient(config: config).saveCall(
                agentId: agent.id, provider: "openai-realtime",
                startedAt: startedAt, endedAt: .now,
                transcript: transcript, costCents: costCents > 0 ? costCents : nil
            )
        }
        dismiss()
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(active ? Color(hex: 0x1A1309) : Theme.text.opacity(0.9))
                    .frame(width: 56, height: 56)
                    .background(
                        active
                            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE6BF77), Color(hex: 0xAC8348)], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.white.opacity(0.09)),
                        in: Circle()
                    )
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.text.opacity(0.9))
            }
        }
    }
}

// Live transcript: scrollable during the call, follows new lines.
struct LiveTranscriptPanel: View {
    let agentName: String
    let transcript: [TranscriptEntry]
    let partial: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcript")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    if transcript.isEmpty && partial == nil {
                        Text("Say something — the conversation shows up here as you talk.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(transcript.enumerated()), id: \.offset) { _, entry in
                        line(role: entry.role, text: entry.text)
                    }
                    if let partial {
                        line(role: "agent", text: partial)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            .onChange(of: transcript.count) { proxy.scrollTo("bottom") }
            .onChange(of: partial) { proxy.scrollTo("bottom") }
            .onAppear { proxy.scrollTo("bottom") }
        }
        .preferredColorScheme(.dark)
    }

    private func line(role: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(role == "user" ? "You" : agentName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(role == "user" ? Theme.muted : Theme.accent)
            Text(text)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(Theme.text.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// The breathing/pulsing brass orb from the design.
struct Orb: View {
    let state: VoiceSessionState
    @State private var animating = false

    var body: some View {
        ZStack {
            if state == .agentSpeaking {
                Circle()
                    .stroke(Theme.accent.opacity(0.28), lineWidth: 1)
                    .frame(width: 150, height: 150)
                    .scaleEffect(animating ? 1.65 : 0.85)
                    .opacity(animating ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.45).repeatForever(autoreverses: false), value: animating)
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.accentBright, Theme.accent, Color(hex: 0x1E2221), Theme.bg],
                        center: .init(x: 0.36, y: 0.3),
                        startRadius: 4, endRadius: 110
                    )
                )
                .frame(width: 122, height: 122)
                .shadow(color: Theme.accent.opacity(0.25), radius: 34)
                .scaleEffect(scale)
                .opacity(state == .thinking ? 0.55 : 1)
                .animation(animation, value: animating)
        }
        .onAppear { animating = true }
    }

    private var scale: CGFloat {
        guard animating else { return 1 }
        switch state {
        case .listening: return 1.055
        case .agentSpeaking: return 1.06
        default: return 1
        }
    }

    private var animation: Animation? {
        switch state {
        case .listening: .easeInOut(duration: 2.8).repeatForever(autoreverses: true)
        case .agentSpeaking: .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        default: .default
        }
    }
}
