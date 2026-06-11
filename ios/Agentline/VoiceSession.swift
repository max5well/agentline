import Foundation

// The provider abstraction (ADR-2). The app codes against this, never
// against a provider SDK directly.

enum VoiceSessionState: Equatable {
    case idle
    case connecting
    case listening
    case agentSpeaking
    case thinking
    case reconnecting
    case ended
}

enum VoiceSessionEvent {
    case state(VoiceSessionState)
    case transcript(TranscriptEntry)
    /// The agent utterance currently being spoken, growing as it streams.
    /// A `.transcript` event with the final text follows when it completes.
    case partialTranscript(String)
    case costTick(cents: Int)
    case error(String)
}

protocol VoiceSession: AnyObject {
    /// Stable provider identifier stored on call records (e.g. "openai-realtime").
    var providerId: String { get }
    /// Model actually used, known once the token is minted; for metering.
    var modelId: String? { get }
    var events: AsyncStream<VoiceSessionEvent> { get }
    func start(agent: Agent) async throws
    func setMuted(_ muted: Bool)
    func end() async
}
