import Foundation
import PushKit

struct IncomingAgentCall {
    let callId: UUID
    let agentId: UUID
    let agentName: String
    let agentEmoji: String
    let brief: String
    let deadline: String?

    var objective: String {
        guard let deadline, !deadline.isEmpty else { return brief }
        return "\(brief)\nDeadline: \(deadline)"
    }
}

extension Notification.Name {
    static let incomingAgentCallAnswered = Notification.Name("incomingAgentCallAnswered")
}

// PushKit wakes the app for a real incoming call. It is deliberately gated by
// an Info.plist switch until the paid Apple team, Push Notifications capability,
// and VoIP APNs key are configured; registering without those cannot work.
final class VoIPPushManager: NSObject, PKPushRegistryDelegate {
    static let shared = VoIPPushManager()
    private static let tokenDefaultsKey = "voip.deviceToken"

    private var registry: PKPushRegistry?

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "AgentlineVoIPPushEnabled") as? Bool == true
    }

    func start() {
        guard Self.isEnabled, BackendConfig.current.isConfigured, registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    func syncStoredToken() {
        guard Self.isEnabled,
              KeychainSession.load() != nil,
              let token = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey) else { return }
        Task {
            try? await BackendClient(config: BackendConfig.current).registerVoIPDevice(
                token: token,
                environment: Self.apnsEnvironment
            )
        }
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
        syncStoredToken()
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP,
              let token = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.tokenDefaultsKey)
        Task {
            try? await BackendClient(config: BackendConfig.current).unregisterVoIPDevice(token: token)
        }
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP,
              let callIdString = payload.dictionaryPayload["call_id"] as? String,
              let callId = UUID(uuidString: callIdString),
              let agentIdString = payload.dictionaryPayload["agent_id"] as? String,
              let agentId = UUID(uuidString: agentIdString),
              let agentName = payload.dictionaryPayload["agent_name"] as? String,
              let brief = payload.dictionaryPayload["brief"] as? String else {
            completion()
            return
        }

        let call = IncomingAgentCall(
            callId: callId,
            agentId: agentId,
            agentName: agentName,
            agentEmoji: payload.dictionaryPayload["agent_emoji"] as? String ?? "🤖",
            brief: String(brief.prefix(1_000)),
            deadline: payload.dictionaryPayload["deadline"] as? String
        )
        // Apple requires every valid VoIP push to be reported to CallKit
        // immediately; completion fires only after CallKit accepts/rejects it.
        CallKitController.shared.reportIncomingCall(call, completion: completion)
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
