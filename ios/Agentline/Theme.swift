import SwiftUI

// Design tokens from agentline-design/screens (brass on near-black).
enum Theme {
    static let bg = Color(hex: 0x050607)
    static let panel = Color(hex: 0x111315)
    static let text = Color(hex: 0xF4F1EC)
    static let muted = Color(hex: 0x9B9A96)
    static let dim = Color(hex: 0x6F706D)
    static let accent = Color(hex: 0xC59B5C)
    static let accentBright = Color(hex: 0xE9C887)
    static let danger = Color(hex: 0xFF453A)
    static let green = Color(hex: 0x6BBF8A)

    static let hairline = Color.white.opacity(0.10)
    static let accentSoft = accent.opacity(0.18)
    static let cardRadius: CGFloat = 22
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// Glass card per the design's .glass class.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}
