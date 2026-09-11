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
    private(set) var modelId: String?
    let providerId = "gemini-live"
    let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

    private let backend: BackendClient
    private let objective: String?
    private let agentInitiated: Bool
    private let incomingCallId: UUID?
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
    private var currentAgent: Agent?
    private var didAttemptReconnect = false
    private var pendingToolCalls = Set<String>()
    private var cancelledToolCalls = Set<String>()
    private var didBeginOpening = false

    // Gemini Live audio contract: PCM16 in at 16 kHz, PCM16 out at 24 kHz.
    private let sendFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true
    )!
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!

    init(
        backend: BackendClient,
        objective: String? = nil,
        agentInitiated: Bool = false,
        incomingCallId: UUID? = nil
    ) {
        self.backend = backend
        self.objective = objective
        self.agentInitiated = agentInitiated
        self.incomingCallId = incomingCallId
        var c: AsyncStream<VoiceSessionEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
        super.init()
    }

    func start(agent: Agent) async throws {
        continuation.yield(.state(.connecting))
        startedAt = Date()
        currentAgent = agent

        // Same CallKit split as OpenAIRealtimeSession: real device goes
        // through CallKit (which activates the audio session), the
        // simulator has no call service so we activate it ourselves.
        #if targetEnvironment(simulator)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                      options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try? audioSession.setActive(true)
        startAudioEngine()
        #else
        do {
            // Bluetooth options make AirPods/headsets routable; CallKit
            // surfaces them in the system audio-route picker.
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP])
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
            if let incomingCallId {
                callId = incomingCallId
            } else {
                callId = try await CallKitController.shared.startOutgoingCall(agentName: agent.name)
            }
        } catch {
            log.error("CallKit unavailable, continuing without: \(error, privacy: .public)")
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                          options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            try? audioSession.setActive(true)
            startAudioEngine()
            callId = nil
        }
        #endif

        do {
            let token = try await backend.mintRealtimeToken(
                agentId: agent.id,
                objective: objective,
                agentInitiated: agentInitiated
            )
            modelId = token.model
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
                // Google Search grounding — server-side tool, no client
                // handling needed. The model only searches when the answer
                // requires current information (verified to work with
                // ephemeral tokens on the Constrained endpoint). The user's
                // MCP tools ride alongside as function declarations (ADR-7);
                // those the app executes via the backend.
                "tools": toolsPayload(token),
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
            ]
        ])
    }

    // Gemini takes one tools array holding both the built-in grounding tool
    // and our function declarations.
    private func toolsPayload(_ token: RealtimeToken) -> [[String: Any]] {
        var tools: [[String: Any]] = [["googleSearch": [:]]]
        if let declarations = token.tools, !declarations.isEmpty {
            tools.append(["functionDeclarations": declarations.map(\.raw)])
        }
        return tools
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
                    Task { await self.reconnectOrFail() }
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

    // One reconnect attempt with a fresh token before giving up —
    // survives network blips. The audio engine keeps running throughout.
    private func reconnectOrFail() async {
        guard !hasEnded else { return }
        guard !didAttemptReconnect, let agent = currentAgent else {
            continuation.yield(.error("Connection lost"))
            await end()
            return
        }
        didAttemptReconnect = true
        setupDone = false
        continuation.yield(.state(.reconnecting))
        ws?.cancel()
        ws = nil
        do {
            try await Task.sleep(for: .seconds(1))
            let token = try await backend.mintRealtimeToken(
                agentId: agent.id,
                objective: objective,
                agentInitiated: agentInitiated
            )
            guard token.provider == providerId else { throw URLError(.badServerResponse) }
            try connect(token: token)
        } catch {
            log.error("reconnect failed: \(error, privacy: .public)")
            continuation.yield(.error("Connection lost"))
            await end()
        }
    }

    // MARK: - Server messages

    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        if json["setupComplete"] != nil {
            setupDone = true
            if let incomingCallId {
                CallKitController.shared.answerReady(incomingCallId)
            } else if let callId {
                CallKitController.shared.reportConnected(callId)
            }
            continuation.yield(.state(.listening))
            beginOpeningIfReady()
            return
        }

        // Tool calls arrive outside serverContent (ADR-7).
        if let toolCall = json["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in calls { runTool(call) }
            return
        }
        if json["toolCallCancellation"] != nil {
            // The turn was interrupted; results for it are no longer wanted.
            cancelledToolCalls.formUnion(pendingToolCalls)
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

    // MARK: - Tools (ADR-7)

    // The backend holds the MCP server credentials and runs the tool; we
    // return its output in the shape Gemini expects and the model carries on.
    private func runTool(_ call: [String: Any]) {
        guard !hasEnded, let name = call["name"] as? String else { return }
        let id = call["id"] as? String
        // Gemini sends args as an object; the backend takes the provider's
        // own JSON so nothing is re-shaped on the way.
        let args = call["args"] as? [String: Any] ?? [:]
        let argumentsJSON = (try? JSONSerialization.data(withJSONObject: args))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        if let id { pendingToolCalls.insert(id) }
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
            if let id {
                self.pendingToolCalls.remove(id)
                guard self.cancelledToolCalls.remove(id) == nil else { return }
            }
            self.continuation.yield(.toolResult(name: name, ok: ok))
            var response: [String: Any] = ["name": name, "response": ["result": output]]
            if let id { response["id"] = id }
            try? self.send(json: ["toolResponse": ["functionResponses": [response]]])
        }
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
            beginOpeningIfReady()
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

    private func beginOpeningIfReady() {
        guard !didBeginOpening, setupDone, engineRunning else { return }
        didBeginOpening = true
        let opening = agentInitiated
            ? "(The caller just answered your call. Lead immediately with the supplied call brief and why you called; do not use a generic greeting.)"
            : "(The call just connected — greet the caller as instructed.)"
        try? send(json: [
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": opening]]]],
                "turnComplete": true,
            ]
        ])
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
