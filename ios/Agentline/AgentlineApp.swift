import SwiftUI

@main
struct AgentlineApp: App {
    @State private var auth = AuthStore.shared

    var body: some Scene {
        WindowGroup {
            // No backend configured → demo mode, no account needed (also
            // keeps UI tests and -screen launch arguments working).
            if BackendConfig.current.isConfigured && auth.session == nil {
                AuthView()
            } else {
                RootTabView()
            }
        }
    }
}
