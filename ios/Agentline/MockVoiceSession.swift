import Foundation

// Simulator development without backend or provider. Cycles through call
// states and emits a fake transcript so every CallView state is testable.
final class MockVoiceSession: VoiceSession {
    let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation
    private var task: Task<Void, Never>?

    init() {
        var c: AsyncStream<VoiceSessionEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    func start(agent: Agent) async throws {
        continuation.yield(.state(.connecting))
        task = Task { [continuation] in
            try? await Task.sleep(for: .seconds(1))
            var cents = 0
            while !Task.isCancelled {
                continuation.yield(.state(.listening))
                try? await Task.sleep(for: .seconds(3))
                continuation.yield(.transcript(.init(role: "user", text: "Tell me why the Congress of Vienna held for forty years.", t: 3)))
                continuation.yield(.state(.thinking))
                try? await Task.sleep(for: .seconds(1.5))
                continuation.yield(.state(.agentSpeaking))
                // Stream the reply word by word like the realtime API does.
                let reply = "It wasn't really about peace, it was about insurance against France ever dominating again…"
                var spoken = ""
                for word in reply.split(separator: " ") {
                    spoken += (spoken.isEmpty ? "" : " ") + word
                    continuation.yield(.partialTranscript(spoken))
                    try? await Task.sleep(for: .seconds(0.18))
                }
                continuation.yield(.transcript(.init(role: "agent", text: reply, t: 5)))
                try? await Task.sleep(for: .seconds(1.2))
                cents += 2
                continuation.yield(.costTick(cents: cents))
            }
        }
    }

    func setMuted(_ muted: Bool) {}

    func end() async {
        task?.cancel()
        continuation.yield(.state(.ended))
        continuation.finish()
    }
}
