import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "dev.max5well.Agentline", category: "gemini")

// Cheap fast tier (ADR-2 impl #2): websocket to the Gemini Live API with an
// ephemeral token minted by the backend (ADR-3). Unlike the OpenAI flow the
// session config (persona, voice) arrives with the token and is sent in the
// setup message; audio is captured and played with AVAudioEngine since
// Gemini Live speaks raw PCM over the socket, not WebRTC.
final class GeminiLiveSession: NSObject, VoiceSession {
    let providerId = "gemini-live"
    let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

    private let backend: BackendClient
    private var ws: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var callId: UUID?
    private var startedAt: Date?
    private var setupDone = false
    private var engineRunning = false
    private var muted = false
    private var hasEnded = false

    private var agentSpeaking = false
    private var currentUtterance = ""
    private var userUtterance = ""

    // Gemini Live audio contract: PCM16 in at 16 kHz, PCM16 out at 24 kHz.
    private let sendFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true
    )!
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!

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

        // Same CallKit split as OpenAIRealtimeSession: real device goes
        // through CallKit (which activates the audio session), the
        // simulator has no call service so we activate it ourselves.
        #if targetEnvironment(simulator)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try? audioSession.setActive(true)
        startAudioEngine()
        #else
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
            CallKitController.shared.onAudioActivated = { [weak self] _ in
                self?.startAudioEngine()
            }
            CallKitController.shared.onAudioDeactivated = { [weak self] _ in
                self?.stopAudioEngine()
            }
            CallKitController.shared.onMuteChanged = { [weak self] muted in
                self?.setMuted(muted)
            }
            CallKitController.shared.onCallEnded = { [weak self] in
                Task { await self?.end() }
            }
            callId = try await CallKitController.shared.startOutgoingCall(agentName: agent.name)
        } catch {
            log.error("CallKit unavailable, continuing without: \(error, privacy: .public)")
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try? audioSession.setActive(true)
            startAudioEngine()
            callId = nil
        }
        #endif

        do {
            let token = try await backend.mintRealtimeToken(agentId: agent.id)
            guard token.provider == providerId else {
                throw NSError(domain: "Agentline", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Backend minted a \(token.provider) token for a \(providerId) session"
                ])
            }
            try connect(token: token)
        } catch {
            log.error("connect failed: \(error, privacy: .public)")
            continuation.yield(.error("Could not connect: \(error.localizedDescription)"))
            await end()
            throw error
        }
    }

    // MARK: - WebSocket

    private func connect(token: RealtimeToken) throws {
        // Ephemeral tokens are only accepted by the Constrained variant of
        // the method — plain BidiGenerateContent rejects them as
        // "unregistered callers".
        var components = URLComponents(
            string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
        )!
        components.queryItems = [URLQueryItem(name: "access_token", value: token.clientSecret)]
        guard let url = components.url else { throw URLError(.badURL) }

        let task = URLSession.shared.webSocketTask(with: url)
        ws = task
        task.resume()
        listen()

        try send(json: [
            "setup": [
                "model": "models/\(token.model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": token.voice ?? "Puck"]]
                    ],
                ],
                "systemInstruction": ["parts": [["text": token.instructions ?? ""]]],
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
            ]
        ])
    }

    private func send(json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        ws?.send(.data(data)) { error in
            if let error { log.error("ws send failed: \(error, privacy: .public)") }
        }
    }

    private func listen() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if !self.hasEnded {
                    log.error("ws receive failed: \(error, privacy: .public)")
                    self.continuation.yield(.error("Connection lost"))
                    Task { await self.end() }
                }
            case .success(let message):
                let data: Data? = switch message {
                case .data(let d): d
                case .string(let s): s.data(using: .utf8)
                @unknown default: nil
                }
                if let data { self.handleServerMessage(data) }
                self.listen()
            }
        }
    }

    // MARK: - Server messages

    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        if json["setupComplete"] != nil {
            setupDone = true
            if let callId { CallKitController.shared.reportConnected(callId) }
            continuation.yield(.state(.listening))
            // The model never speaks unprompted; nudge the greeting turn
            // (instructions for it are in the system instruction).
            try? send(json: [
                "clientContent": [
                    "turns": [["role": "user", "parts": [["text": "(The call just connected — greet the caller as instructed.)"]]]],
                    "turnComplete": true,
                ]
            ])
            return
        }

        guard let content = json["serverContent"] as? [String: Any] else { return }

        if content["interrupted"] as? Bool == true {
            // Drop queued agent audio immediately; keep what was actually
            // said so far as the final transcript line.
            player.stop()
            player.play()
            flushAgentUtterance(at: elapsed)
            agentSpeaking = false
            continuation.yield(.state(.listening))
            return
        }

        if let input = content["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String {
            userUtterance += text
        }

        if let output = content["outputTranscription"] as? [String: Any],
           let text = output["text"] as? String {
            markAgentSpeaking(at: elapsed)
            currentUtterance += text
            continuation.yield(.partialTranscript(currentUtterance))
        }

        if let turn = content["modelTurn"] as? [String: Any],
           let parts = turn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any],
                   let b64 = inline["data"] as? String,
                   let pcm = Data(base64Encoded: b64) {
                    markAgentSpeaking(at: elapsed)
                    schedulePlayback(pcm)
                }
            }
        }

        if content["turnComplete"] as? Bool == true {
            flushAgentUtterance(at: elapsed)
            agentSpeaking = false
            continuation.yield(.state(.listening))
        }
    }

    private func markAgentSpeaking(at elapsed: TimeInterval) {
        guard !agentSpeaking else { return }
        agentSpeaking = true
        // The user turn is over once the agent answers; flush its transcript.
        if !userUtterance.isEmpty {
            continuation.yield(.transcript(.init(role: "user", text: userUtterance, t: elapsed)))
            userUtterance = ""
        }
        continuation.yield(.state(.agentSpeaking))
    }

    private func flushAgentUtterance(at elapsed: TimeInterval) {
        guard !currentUtterance.isEmpty else { return }
        continuation.yield(.transcript(.init(role: "agent", text: currentUtterance, t: elapsed)))
        currentUtterance = ""
    }

    // MARK: - Audio

    private func startAudioEngine() {
        guard !engineRunning else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: sendFormat) else {
            continuation.yield(.error("Microphone unavailable"))
            return
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.sendMicrophone(buffer: buffer, converter: converter)
        }

        do {
            try engine.start()
            player.play()
            engineRunning = true
        } catch {
            log.error("audio engine start failed: \(error, privacy: .public)")
            continuation.yield(.error("Audio unavailable: \(error.localizedDescription)"))
        }
    }

    private func stopAudioEngine() {
        guard engineRunning else { return }
        engineRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
    }

    private func sendMicrophone(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        guard setupDone, !muted, ws != nil else { return }

        let ratio = sendFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: sendFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0,
              let channel = converted.int16ChannelData?[0] else { return }

        let data = Data(bytes: channel, count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
        try? send(json: [
            "realtimeInput": [
                "audio": ["data": data.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]
            ]
        ])
    }

    private func schedulePlayback(_ pcm: Data) {
        let frames = pcm.count / MemoryLayout<Int16>.size
        guard frames > 0, engineRunning,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                channel[i] = Float(Int16(littleEndian: samples[i])) / 32768
            }
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        self.muted = muted
    }

    func end() async {
        guard !hasEnded else { return }
        hasEnded = true
        log.info("session end() called")
        CallKitController.shared.onCallEnded = nil
        CallKitController.shared.onAudioActivated = nil
        CallKitController.shared.onAudioDeactivated = nil
        CallKitController.shared.onMuteChanged = nil
        CallKitController.shared.endCall()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        stopAudioEngine()
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        flushAgentUtterance(at: elapsed)
        continuation.yield(.state(.ended))
        continuation.finish()
    }
}
