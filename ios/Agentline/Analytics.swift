import Foundation
import PostHog

// Product analytics (PostHog). Every call is a no-op until `apiKey` is
// filled with the project key from posthog.com — safe to ship disabled.
// Events answer the admin KPIs: activation funnel, engagement, product
// mix. No transcript content or persona text is ever captured.
enum Analytics {
    // Local builds can set POSTHOG_API_KEY and POSTHOG_HOST in the Xcode
    // scheme. Release builds can provide the same values through Info.plist.
    // The project key is a public ingestion key; never put a personal API key here.
    private static var apiKey: String {
        ProcessInfo.processInfo.environment["POSTHOG_API_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String
            ?? ""
    }

    private static var host: String {
        ProcessInfo.processInfo.environment["POSTHOG_HOST"]
            ?? Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String
            ?? "https://eu.i.posthog.com"
    }

    static var enabled: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("phc_")
    }

    static func configure() {
        guard enabled else { return }
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
    }

    static func identify(userId: String) {
        guard enabled else { return }
        PostHogSDK.shared.identify(userId)
    }

    static func reset() {
        guard enabled else { return }
        PostHogSDK.shared.reset()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard enabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
