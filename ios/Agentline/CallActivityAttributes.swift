import ActivityKit
import Foundation

// Shared between the app (starts/updates the activity) and the widget
// extension (renders it) — DESIGN-SPEC screen 10.
struct CallActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stateLabel: String   // Listening / Speaking / Thinking / Reconnecting
        var startedAt: Date
    }

    var agentName: String
    var agentEmoji: String
}
