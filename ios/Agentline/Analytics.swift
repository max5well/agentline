import Foundation
import PostHog

// Product analytics (PostHog). Every call is a no-op until `apiKey` is
// filled with the project key from posthog.com — safe to ship disabled.
// Events answer the admin KPIs: activation funnel, engagement, product
// mix. No transcript content or persona text is ever captured.
enum Analytics {
    // TODO(Max): paste the PostHog project API key (phc_…) once the
    // PostHog project exists, and pick the matching host below.
    private static let apiKey = ""
    private static let host = "https://eu.i.posthog.com"

    static var enabled: Bool { !apiKey.isEmpty }

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
