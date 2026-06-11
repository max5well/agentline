import Foundation
import WebRTC

// Launch provider (ADR-2 impl #1): WebRTC straight to OpenAI Realtime with
// an ephemeral client secret minted by the backend (ADR-3). The agent's
// persona and voice are baked into the token server-side, so no session
// config is sent from the app.
final class OpenAIRealtimeSession: NSObject, VoiceSession {
    let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

    private let backend: BackendClient
    private let factory = RTCPeerConnectionFactory()
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var callId: UUID?
    private var startedAt: Date?
    private var agentSpeaking = false

    init(backend: BackendClient) {
        self.backend = backend
        var c: AsyncStream<VoiceSessionEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
        super.init()
    }

    func start(agent: Agent) async throws {
        continuation.yield(.state(.connecting))
        startedAt = Date()

        // CallKit first: it owns the audio session (manual audio mode) and
        // activates it via the provider delegate once the call is reported.
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        CallKitController.shared.onMuteChanged = { [weak self] muted in
            self?.audioTrack?.isEnabled = !muted
        }
        CallKitController.shared.onCallEnded = { [weak self] in
            Task { await self?.end() }
        }
        callId = try await CallKitController.shared.startOutgoingCall(agentName: agent.name)

        do {
            let token = try await backend.mintRealtimeToken(agentId: agent.id)
            try await connect(token: token)
            if let callId { CallKitController.shared.reportConnected(callId) }
            continuation.yield(.state(.listening))
        } catch {
            continuation.yield(.error("Could not connect: \(error.localizedDescription)"))
            await end()
            throw error
        }
    }

    private func connect(token: RealtimeToken) async throws {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw URLError(.cannotConnectToHost)
        }
        peerConnection = pc

        let audioSource = factory.audioSource(with: constraints)
        let track = factory.audioTrack(with: audioSource, trackId: "mic0")
        pc.add(track, streamIds: ["agentline"])
        audioTrack = track

        let channel = pc.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration())
        channel?.delegate = self
        dataChannel = channel

        let offer = try await pc.offer(for: constraints)
        try await pc.setLocalDescription(offer)

        let answerSDP = try await exchangeSDP(offer: offer.sdp, token: token)
        try await pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answerSDP))
    }

    private func exchangeSDP(offer: String, token: RealtimeToken) async throws -> String {
        var components = URLComponents(string: "https://api.openai.com/v1/realtime/calls")!
        components.queryItems = [URLQueryItem(name: "model", value: token.model)]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token.clientSecret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = offer.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let sdp = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return sdp
    }

    func setMuted(_ muted: Bool) {
        audioTrack?.isEnabled = !muted
    }

    func end() async {
        CallKitController.shared.onCallEnded = nil
        CallKitController.shared.endCall()
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
        audioTrack = nil
        continuation.yield(.state(.ended))
        continuation.finish()
    }

    // MARK: - Realtime server events (over the data channel)

    private func handleServerEvent(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        switch type {
        case "input_audio_buffer.speech_started":
            agentSpeaking = false
            continuation.yield(.state(.listening))
        case "input_audio_buffer.speech_stopped", "response.created":
            if !agentSpeaking { continuation.yield(.state(.thinking)) }
        case "response.output_audio_transcript.delta":
            if !agentSpeaking {
                agentSpeaking = true
                continuation.yield(.state(.agentSpeaking))
            }
        case "response.output_audio_transcript.done":
            if let text = json["transcript"] as? String {
                continuation.yield(.transcript(.init(role: "agent", text: text, t: elapsed)))
            }
        case "conversation.item.input_audio_transcription.completed":
            if let text = json["transcript"] as? String {
                continuation.yield(.transcript(.init(role: "user", text: text, t: elapsed)))
            }
        case "response.done":
            agentSpeaking = false
            continuation.yield(.state(.listening))
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Realtime error"
            continuation.yield(.error(message))
        default:
            break
        }
    }
}

extension OpenAIRealtimeSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        handleServerEvent(buffer.data)
    }
}

extension OpenAIRealtimeSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected:
            continuation.yield(.state(.reconnecting))
        case .failed:
            continuation.yield(.error("Connection lost"))
            Task { await end() }
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
    }
}
