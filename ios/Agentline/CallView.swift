import ActivityKit
import AVKit
import SwiftUI

struct CallView: View {
    let agent: Agent
    let objective: String?
    let agentInitiated: Bool
    let session: any VoiceSession

    init(
        agent: Agent,
        objective: String? = nil,
        agentInitiated: Bool = false,
        session: any VoiceSession
    ) {
        self.agent = agent
        self.objective = objective
        self.agentInitiated = agentInitiated
        self.session = session
    }

    @Environment(\.dismiss) private var dismiss
    @State private var state: VoiceSessionState = .connecting
    @State private var transcript: [TranscriptEntry] = []
    @State private var costCents = 0
    @State private var startedAt = Date.now
    @State private var muted = false
    @State private var errorMessage: String?
    @State private var partialCaption: String?
    @State private var showTranscript = false
    @State private var activity: Activity<CallActivityAttributes>?
    @State private var finishing = false
    /// Tool the agent is running right now, shown so a pause has a reason (ADR-7).
    @State private var activeTool: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            CallAvatar(agent: agent, state: state)
            Spacer()
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 18)
            }
            controls
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        // Always dark, like the Phone app (DESIGN-SPEC §3.3).
        .environment(\.colorScheme, .dark)
        .task {
            for await event in session.events {
                switch event {
                case .state(let s):
                    state = s
                    updateActivity()
                    // On error, stay on screen so the message is readable;
                    // the user leaves via the hang-up button.
                    if s == .ended && errorMessage == nil { await endAndDismiss() }
                case .transcript(let entry):
                    transcript.append(entry)
                    if entry.role == "agent" { partialCaption = nil }
                case .partialTranscript(let text):
                    partialCaption = text
                case .costTick(let cents): costCents = cents
                case .toolCall(let name):
                    activeTool = Self.friendlyToolName(name)
                case .toolResult:
                    // The agent says out loud whether it worked, so the line
                    // just goes away.
                    activeTool = nil
                case .error(let message): errorMessage = message
                }
            }
        }
        .task {
            Analytics.capture("call_started", [
                "tier": agent.tier.rawValue, "provider": session.providerId,
                "language": agent.language ?? "English",
                "direction": agentInitiated ? "agent_initiated" : "user_initiated",
            ])
            try? await session.start(agent: agent)
        }
        .onAppear(perform: startActivity)
        .sheet(isPresented: $showTranscript) {
            LiveTranscriptPanel(agentName: agent.name, transcript: transcript, partial: partialCaption)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(agent.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            // "State · mm:ss · €cost" in one secondary line (§3.3).
            HStack(spacing: 8) {
                Text(stateLabel)
                Text("·")
                Text(startedAt, style: .timer)
                Text("·")
                Text(String(format: "€%.2f", Double(costCents) / 100))
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
            if session is MockVoiceSession {
                Text("Demo mode — no backend configured (Settings)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }
        }
    }

    // "calendar_create_event" reads badly at a glance from a car mount.
    static func friendlyToolName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private var stateLabel: String {
        if let activeTool { return "Using \(activeTool)" }
        return switch state {
        case .idle, .connecting: "Connecting"
        case .listening: "Listening"
        case .agentSpeaking: "Speaking"
        case .thinking: "Thinking"
        case .reconnecting: "Reconnecting"
        case .ended: "Ended"
        }
    }

    // Three controls (§3.3 v2 — captions button removed, the transcript
    // sheet covers it).
    private var controls: some View {
        VStack(spacing: 22) {
            HStack(spacing: 26) {
                ControlButton(icon: "mic.slash.fill", label: "mute", active: muted) {
                    muted.toggle()
                    session.setMuted(muted)
                }
                AudioRouteButton()
                ControlButton(icon: "doc.text.fill", label: "transcript", active: showTranscript) {
                    showTranscript = true
                }
            }
            Button {
                Task { await endAndDismiss() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Color.red, in: Circle())
            }
            .accessibilityLabel("End call")
        }
        .padding(.bottom, 10)
    }

    // Lock-screen card + Dynamic Island while the call runs (#29).
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CallActivityAttributes(agentName: agent.name, agentEmoji: agent.emoji)
        let content = ActivityContent(
            state: CallActivityAttributes.ContentState(stateLabel: stateLabel, startedAt: startedAt),
            staleDate: nil
        )
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    private func updateActivity() {
        guard let activity else { return }
        let content = ActivityContent(
            state: CallActivityAttributes.ContentState(stateLabel: stateLabel, startedAt: startedAt),
            staleDate: nil
        )
        Task { await activity.update(content) }
    }

    private func endAndDismiss() async {
        // Reachable from the hang-up button, the session's .ended event,
        // and CallKit's end action — exactly one may save the call.
        guard !finishing else { return }
        finishing = true
        if let activity {
            let content = ActivityContent(
                state: CallActivityAttributes.ContentState(stateLabel: "Ended", startedAt: startedAt),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
        await session.end()
        Analytics.capture("call_ended", [
            "duration_seconds": Int(Date.now.timeIntervalSince(startedAt)),
            "tier": agent.tier.rawValue, "provider": session.providerId,
            "model": session.modelId ?? "unknown", "cost_cents": costCents,
            "transcript_turns": transcript.count,
            "had_error": errorMessage != nil,
            "direction": agentInitiated ? "agent_initiated" : "user_initiated",
        ])
        // ADR-4: transcript is buffered live and POSTed on hangup; the
        // backend's summary worker fills in the rest.
        let config = BackendConfig.current
        if config.isConfigured, !(session is MockVoiceSession) {
            try? await BackendClient(config: config).saveCall(
                agentId: agent.id, provider: session.providerId, model: session.modelId,
                startedAt: startedAt, endedAt: .now,
                transcript: transcript, costCents: costCents > 0 ? costCents : nil,
                objective: objective
            )
        }
        dismiss()
    }
}

// System audio-route picker (speaker / AirPods / headset) styled like the
// other call controls. AVRoutePickerView opens the same popover the Phone
// app uses, so Bluetooth and wired routes are switchable mid-call.
struct AudioRouteButton: View {
    var body: some View {
        VStack(spacing: 7) {
            RoutePickerView()
                .frame(width: 62, height: 62)
                .background(Color.white.opacity(0.16), in: Circle())
            Text("audio")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// 62pt circles, white 16% fill; active = filled white, black icon (§3.3).
struct ControlButton: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(active ? .black : .white)
                    .frame(width: 62, height: 62)
                    .background(active ? Color.white : Color.white.opacity(0.16), in: Circle())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
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
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    if transcript.isEmpty && partial == nil {
                        Text("Say something — the conversation shows up here as you talk.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
    }

    private func line(role: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(role == "user" ? "You" : agentName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(role == "user" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
