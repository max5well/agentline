import Foundation
import OSLog
import WebRTC

private let log = Logger(subsystem: "dev.max5well.Agentline", category: "realtime")

// Launch provider (ADR-2 impl #1): WebRTC straight to OpenAI Realtime with
// an ephemeral client secret minted by the backend (ADR-3). The agent's
// persona and voice are baked into the token server-side, so no session
// config is sent from the app.
final class OpenAIRealtimeSession: NSObject, VoiceSession {
    private(set) var modelId: String?
    let providerId = "openai-realtime"
    let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

    private let backend: BackendClient
    private let objective: String?
    private let factory = RTCPeerConnectionFactory()
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var callId: UUID?
    private var startedAt: Date?
    private var agentSpeaking = false
    private var currentUtterance = ""
    private var currentAgent: Agent?
    private var reconnectTask: Task<Void, Never>?
    private var didAttemptReconnect = false
    // Function calls surface on two events; whichever lands first wins and
    // the other is ignored (ADR-7).
    private var handledToolCalls = Set<String>()

    init(backend: BackendClient, objective: String? = nil) {
        self.backend = backend
        self.objective = objective
        var c: AsyncStream<VoiceSessionEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
        super.init()
    }

    func start(agent: Agent) async throws {
        continuation.yield(.state(.connecting))
        startedAt = Date()
        currentAgent = agent

        // CallKit first: it owns the audio session (manual audio mode) and
        // activates it via the provider delegate once the call is reported.
        // The simulator has no call service — CallKit accepts the call and
        // then resets it, killing the session. Skip it there and let WebRTC
        // manage the audio session itself. Same fallback if CallKit throws
        // (e.g. running as Designed-for-iPhone on Mac).
        #if targetEnvironment(simulator)
        // Configure the audio session before WebRTC initializes its
        // voice-processing unit — uninitialized sessions abort in the
        // simulator's audio stack (CoreAudio RPC timeout).
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.useManualAudio = false
        rtcSession.lockForConfiguration()
        try? rtcSession.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try? rtcSession.setActive(true)
        rtcSession.unlockForConfiguration()
        #else
        do {
            RTCAudioSession.sharedInstance().useManualAudio = true
            RTCAudioSession.sharedInstance().isAudioEnabled = false
            // CallKit owns the AVAudioSession; hand activation over to WebRTC.
            CallKitController.shared.onAudioActivated = { session in
                let rtcSession = RTCAudioSession.sharedInstance()
                rtcSession.audioSessionDidActivate(session)
                rtcSession.isAudioEnabled = true
            }
            CallKitController.shared.onAudioDeactivated = { session in
                let rtcSession = RTCAudioSession.sharedInstance()
                rtcSession.isAudioEnabled = false
                rtcSession.audioSessionDidDeactivate(session)
            }
            CallKitController.shared.onMuteChanged = { [weak self] muted in
                self?.audioTrack?.isEnabled = !muted
            }
            CallKitController.shared.onCallEnded = { [weak self] in
                Task { await self?.end() }
            }
            callId = try await CallKitController.shared.startOutgoingCall(agentName: agent.name)
        } catch {
            log.error("CallKit unavailable, continuing without: \(error, privacy: .public)")
            RTCAudioSession.sharedInstance().useManualAudio = false
            callId = nil
        }
        #endif

        do {
            let token = try await backend.mintRealtimeToken(agentId: agent.id, objective: objective)
            modelId = token.model
            try await connect(token: token)
            if let callId { CallKitController.shared.reportConnected(callId) }
            continuation.yield(.state(.listening))
        } catch {
            log.error("connect failed: \(error, privacy: .public)")
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

    private var hasEnded = false

    func end() async {
        guard !hasEnded else { return }
        hasEnded = true
        log.info("session end() called")
        reconnectTask?.cancel()
        CallKitController.shared.onCallEnded = nil
        CallKitController.shared.onAudioActivated = nil
        CallKitController.shared.onAudioDeactivated = nil
        CallKitController.shared.endCall()
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
        audioTrack = nil
        continuation.yield(.state(.ended))
        continuation.finish()
    }

    // MARK: - Tools (ADR-7)

    private func sendClientEvent(_ event: [String: Any]) {
        guard let channel = dataChannel, channel.readyState == .open,
              let payload = try? JSONSerialization.data(withJSONObject: event) else { return }
        channel.sendData(RTCDataBuffer(data: payload, isBinary: false))
    }

    // The model asked for one of the user's MCP tools. The backend holds the
    // server credentials and runs it; the result goes back as a function call
    // output, then the model is asked to speak again.
    private func runTool(name: String, callId: String, argumentsJSON: String) {
        guard !hasEnded, !handledToolCalls.contains(callId) else { return }
        handledToolCalls.insert(callId)
        continuation.yield(.toolCall(name: name))
        continuation.yield(.state(.thinking))

        Task { [weak self] in
            guard let self else { return }
            var output: String
            var ok = true
            do {
                let response = try await self.backend.mcpCallTool(name: name, argumentsJSON: argumentsJSON)
                output = response.result
                ok = !response.isError
            } catch {
                log.error("tool call failed: \(error, privacy: .public)")
                output = "The tool could not be reached: \(error.localizedDescription)"
                ok = false
            }
            guard !self.hasEnded else { return }
            self.continuation.yield(.toolResult(name: name, ok: ok))
            self.sendClientEvent([
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": output,
                ],
            ])
            // The model does not resume on its own after a tool output.
            self.sendClientEvent(["type": "response.create"])
        }
    }

    // MARK: - Realtime server events (over the data channel)

    private func handleServerEvent(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        log.debug("server event: \(type, privacy: .public)")
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
            if let delta = json["delta"] as? String {
                currentUtterance += delta
                continuation.yield(.partialTranscript(currentUtterance))
            }
        case "response.output_audio_transcript.done":
            currentUtterance = ""
            if let text = json["transcript"] as? String {
                continuation.yield(.transcript(.init(role: "agent", text: text, t: elapsed)))
            }
        case "conversation.item.input_audio_transcription.completed":
            if let text = json["transcript"] as? String {
                continuation.yield(.transcript(.init(role: "user", text: text, t: elapsed)))
            }
        case "response.function_call_arguments.done":
            if let callId = json["call_id"] as? String,
               let name = json["name"] as? String {
                runTool(name: name, callId: callId,
                        argumentsJSON: json["arguments"] as? String ?? "{}")
            }
        case "response.output_item.done":
            // Carries the complete item, so it also covers models that omit
            // the name from the arguments event.
            if let item = json["item"] as? [String: Any],
               item["type"] as? String == "function_call",
               let callId = item["call_id"] as? String,
               let name = item["name"] as? String {
                runTool(name: name, callId: callId,
                        argumentsJSON: item["arguments"] as? String ?? "{}")
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
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        // The model never speaks unprompted; request the greeting turn
        // (instructions for it are in the session config) once the
        // channel opens.
        guard dataChannel.readyState == .open,
              let payload = try? JSONSerialization.data(withJSONObject: ["type": "response.create"]) else { return }
        dataChannel.sendData(RTCDataBuffer(data: payload, isBinary: false))
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        handleServerEvent(buffer.data)
    }
}

extension OpenAIRealtimeSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        log.info("ICE state: \(newState.rawValue)")
        switch newState {
        case .disconnected:
            // WebRTC often recovers on its own; show the state, and if it
            // hasn't healed shortly, rebuild the transport.
            continuation.yield(.state(.reconnecting))
            scheduleReconnect(after: 4)
        case .failed:
            scheduleReconnect(after: 0)
        case .connected, .completed:
            reconnectTask?.cancel()
            reconnectTask = nil
        default:
            break
        }
    }

    // One full reconnect attempt (fresh token, new peer connection) before
    // giving up — survives network blips like subway tunnels.
    private func scheduleReconnect(after seconds: Double) {
        guard reconnectTask == nil, !hasEnded, let agent = currentAgent else {
            if reconnectTask == nil, !hasEnded {
                continuation.yield(.error("Connection lost"))
                Task { await end() }
            }
            return
        }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.hasEnded, !Task.isCancelled else { return }
            guard !self.didAttemptReconnect else {
                self.continuation.yield(.error("Connection lost"))
                await self.end()
                return
            }
            self.didAttemptReconnect = true
            log.info("attempting reconnect")
            self.continuation.yield(.state(.reconnecting))
            self.dataChannel?.close()
            self.peerConnection?.close()
            self.dataChannel = nil
            self.peerConnection = nil
            do {
                let token = try await self.backend.mintRealtimeToken(agentId: agent.id, objective: objective)
                try await self.connect(token: token)
                self.continuation.yield(.state(.listening))
                self.reconnectTask = nil
            } catch {
                log.error("reconnect failed: \(error, privacy: .public)")
                self.continuation.yield(.error("Connection lost"))
                await self.end()
            }
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
