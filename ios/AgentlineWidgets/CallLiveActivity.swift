import ActivityKit
import SwiftUI
import WidgetKit

// Lock-screen call card + Dynamic Island (DESIGN-SPEC screen 10).
@main
struct AgentlineWidgets: WidgetBundle {
    var body: some Widget {
        CallLiveActivity()
    }
}

struct CallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            // Lock screen card
            HStack(spacing: 12) {
                avatar(context.attributes, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.agentName)
                        .font(.headline)
                    Text(context.state.stateLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.startedAt, style: .timer)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.green)
                    .frame(maxWidth: 70)
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    avatar(context.attributes, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.agentName).font(.headline)
                        Text(context.state.stateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.green)
                        .frame(maxWidth: 56)
                }
            } compactLeading: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.green)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            }
        }
    }

    private func avatar(_ attributes: CallActivityAttributes, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.blue.gradient)
            if attributes.agentEmoji.isEmpty {
                Text(String(attributes.agentName.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(attributes.agentEmoji)
                    .font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
    }
}
