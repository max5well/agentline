import SwiftUI

// One avatar renderer for every size in the app (DESIGN-SPEC §5):
// list rows 38pt, summary 62pt, editor 64pt, in-call 130pt.
// Stage 1 sources: emoji on a per-agent color, or a monogram fallback
// when the emoji is empty. Photo/generated come with backend storage.
struct AgentAvatar: View {
    let agent: Agent
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(agent.avatarColor.gradient)
            if agent.emoji.isEmpty {
                Text(agent.monogram)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text(agent.emoji)
                    .font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
    }
}

extension Agent {
    var monogram: String {
        let words = name.split(separator: " ").prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    // Stable per-agent identity color from the iOS system palette
    // (derived from the id until avatar config is persisted).
    // Not Hashable.hashValue — that's seeded per process launch.
    var avatarColor: Color {
        let palette: [Color] = [.blue, .green, .indigo, .orange, .pink, .purple, .teal]
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

// In-call avatar with the animated state ring (replaces the brass orb;
// keep this component swappable — DESIGN-SPEC §3.3 open item).
struct CallAvatar: View {
    let agent: Agent
    let state: VoiceSessionState
    @State private var animating = false

    var body: some View {
        ZStack {
            if state == .agentSpeaking {
                Circle()
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 158, height: 158)
                    .scaleEffect(animating ? 1.35 : 0.95)
                    .opacity(animating ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: animating)
            }
            Circle()
                .stroke(ringColor, lineWidth: 3)
                .frame(width: 146, height: 146)
                .scaleEffect(ringScale)
                .animation(ringAnimation, value: animating)
            AgentAvatar(agent: agent, size: 130)
        }
        .onAppear { animating = true }
    }

    private var ringColor: Color {
        switch state {
        case .agentSpeaking: .accentColor
        case .listening: .accentColor.opacity(0.55)
        case .thinking, .connecting, .reconnecting: .white.opacity(0.25)
        case .idle, .ended: .white.opacity(0.15)
        }
    }

    private var ringScale: CGFloat {
        guard animating else { return 1 }
        switch state {
        case .listening: return 1.03
        case .agentSpeaking: return 1.05
        default: return 1
        }
    }

    private var ringAnimation: Animation? {
        switch state {
        case .listening: .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
        case .agentSpeaking: .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        default: .default
        }
    }
}
