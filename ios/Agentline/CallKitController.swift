import AVFoundation
import CallKit

// System call integration: lock-screen controls, audio session ownership,
// interruption by real calls. Real voice sessions report through this;
// MockVoiceSession never touches it so simulator UI work stays simple.
final class CallKitController: NSObject {
    static let shared = CallKitController()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallId: UUID?
    private var incomingCalls: [UUID: IncomingAgentCall] = [:]
    private var pendingAnswerActions: [UUID: CXAnswerCallAction] = [:]
    private var answeredCallAwaitingUI: IncomingAgentCall?
    private var activeAudioSession: AVAudioSession?

    // Set by the active voice session before starting a call.
    var onMuteChanged: ((Bool) -> Void)?
    var onCallEnded: (() -> Void)?
    // CallKit owns the AVAudioSession; what happens on activation is
    // provider-specific (WebRTC handoff vs. starting an AVAudioEngine),
    // so the active session installs these too.
    var onAudioActivated: ((AVAudioSession) -> Void)? {
        didSet {
            if let activeAudioSession { onAudioActivated?(activeAudioSession) }
        }
    }
    var onAudioDeactivated: ((AVAudioSession) -> Void)?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func startOutgoingCall(agentName: String) async throws -> UUID {
        let callId = UUID()
        currentCallId = callId
        let handle = CXHandle(type: .generic, value: agentName)
        let action = CXStartCallAction(call: callId, handle: handle)
        try await callController.requestTransaction(with: [action])
        return callId
    }

    func reportConnected(_ callId: UUID) {
        provider.reportOutgoingCall(with: callId, connectedAt: Date())
    }

    func reportIncomingCall(_ call: IncomingAgentCall, completion: @escaping () -> Void) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: call.agentName)
        update.localizedCallerName = call.agentName
        update.hasVideo = false
        incomingCalls[call.callId] = call
        provider.reportNewIncomingCall(with: call.callId, update: update) { [weak self] error in
            if error != nil {
                self?.incomingCalls.removeValue(forKey: call.callId)
            } else {
                self?.currentCallId = call.callId
            }
            completion()
        }
    }

    func reportFailed(_ callId: UUID) {
        incomingCalls.removeValue(forKey: callId)
        pendingAnswerActions.removeValue(forKey: callId)?.fail()
        if currentCallId == callId { currentCallId = nil }
        provider.reportCall(with: callId, endedAt: .now, reason: .failed)
    }

    // Keep the system incoming-call UI on “connecting” until the realtime
    // transport is actually ready, as CallKit recommends.
    func answerReady(_ callId: UUID) {
        pendingAnswerActions.removeValue(forKey: callId)?.fulfill()
    }

    // NotificationCenter delivery can race a cold SwiftUI scene. Keep one
    // answered call until RootTabView claims it, so a fast answer is not lost.
    func claimAnsweredCall(_ callId: UUID? = nil) -> IncomingAgentCall? {
        guard let call = answeredCallAwaitingUI,
              callId == nil || call.callId == callId else { return nil }
        answeredCallAwaitingUI = nil
        return call
    }

    func endCall() {
        guard let callId = currentCallId else { return }
        currentCallId = nil
        let action = CXEndCallAction(call: callId)
        callController.requestTransaction(with: [action]) { _ in }
    }
}

extension CallKitController: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        currentCallId = nil
        incomingCalls.removeAll()
        pendingAnswerActions.values.forEach { $0.fail() }
        pendingAnswerActions.removeAll()
        answeredCallAwaitingUI = nil
        activeAudioSession = nil
        onCallEnded?()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        incomingCalls.removeValue(forKey: action.callUUID)
        pendingAnswerActions.removeValue(forKey: action.callUUID)?.fail()
        currentCallId = nil
        onCallEnded?()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = incomingCalls.removeValue(forKey: action.callUUID) else {
            action.fail()
            return
        }
        currentCallId = action.callUUID
        pendingAnswerActions[action.callUUID] = action
        answeredCallAwaitingUI = call
        NotificationCenter.default.post(name: .incomingAgentCallAnswered, object: call)
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMuteChanged?(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        activeAudioSession = audioSession
        onAudioActivated?(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        activeAudioSession = nil
        onAudioDeactivated?(audioSession)
    }
}
