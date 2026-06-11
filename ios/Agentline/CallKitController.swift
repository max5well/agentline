import CallKit
import WebRTC

// System call integration: lock-screen controls, audio session ownership,
// interruption by real calls. Real voice sessions report through this;
// MockVoiceSession never touches it so simulator UI work stays simple.
final class CallKitController: NSObject {
    static let shared = CallKitController()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallId: UUID?

    // Set by the active voice session before starting a call.
    var onMuteChanged: ((Bool) -> Void)?
    var onCallEnded: (() -> Void)?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
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
        onCallEnded?()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        currentCallId = nil
        onCallEnded?()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMuteChanged?(action.isMuted)
        action.fulfill()
    }

    // CallKit owns the AVAudioSession; hand activation over to WebRTC.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.audioSessionDidActivate(audioSession)
        rtcSession.isAudioEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.isAudioEnabled = false
        rtcSession.audioSessionDidDeactivate(audioSession)
    }
}
