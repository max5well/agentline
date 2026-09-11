import SwiftUI

@main
struct AgentlineApp: App {
    @State private var auth = AuthStore.shared

    init() {
        Analytics.configure()
        // PushKit requires its registry early in app launch so a terminated
        // app can be woken and report the incoming call to CallKit in time.
        VoIPPushManager.shared.start()
        if let userId = AuthStore.shared.session?.userId {
            Analytics.identify(userId: userId)
        }
    }

    var body: some Scene {
        WindowGroup {
            // No backend configured → demo mode, no account needed (also
            // keeps UI tests and -screen launch arguments working).
            if BackendConfig.current.isConfigured && auth.session == nil {
                AuthView()
            } else {
                RootTabView()
                    .task {
                        VoIPPushManager.shared.syncStoredToken()
                    }
            }
        }
    }
}
