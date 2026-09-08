import SwiftUI

/// One accent, three functional states. Everything else is neutral — the popover is a
/// gauge, not a dashboard.
enum Theme {
    static let popoverWidth: CGFloat = 344

    static func tint(for percent: Double) -> Color {
        switch percent {
        case ..<80: .accentColor
        case ..<95: .orange
        default: .red
        }
    }

    static let trackOpacity: Double = 0.12

    /// Series colours follow the window order — session, weekly, then per-model — so a
    /// line keeps its colour from one account to the next instead of being assigned
    /// alphabetically by Swift Charts.
    static let seriesPalette: [Color] = [.accentColor, .teal, .orange, .purple, .pink]
}

extension Text {
    /// Numbers that change every poll should not make the layout jitter.
    func numeric() -> Text { self.monospacedDigit() }
}
