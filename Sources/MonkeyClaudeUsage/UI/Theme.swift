import AppKit
import SwiftUI

/// One accent, two warning states, everything else neutral.
///
/// Nothing here comes from `.accentColor`. The system accent is whatever the user picked
/// for their buttons — blue by default — and blue at eleven points on a dark popover is
/// barely legible. These are fixed, and each carries a lighter variant for dark mode and
/// a deeper one for light, because a single sRGB value cannot be right on both.
enum Theme {
    static let popoverWidth: CGFloat = 344
    static let trackOpacity: Double = 0.12

    /// The terracotta of the app icon's gauge — the app already has an accent, it just
    /// was not being used.
    static let accent = adaptive(dark: (0.898, 0.510, 0.376), light: (0.769, 0.365, 0.235))
    static let warning = adaptive(dark: (0.949, 0.667, 0.263), light: (0.776, 0.494, 0.106))
    static let critical = adaptive(dark: (0.945, 0.353, 0.376), light: (0.816, 0.180, 0.208))

    /// Bars carry the state as colour: they are shapes, and a shape has nothing else to
    /// say it with.
    static func barTint(for percent: Double) -> Color {
        switch percent {
        case ..<80: accent
        case ..<95: warning
        default: critical
        }
    }

    /// Numbers stay plain text until something is worth warning about. Tinting every
    /// figure costs contrast and spends the reader's attention on the ordinary case.
    static func numberTint(for percent: Double) -> Color {
        percent < 80 ? .primary : barTint(for: percent)
    }

    /// Series colours follow the window order — session, weekly, then per-model — so a
    /// line keeps its colour from one account to the next instead of being assigned
    /// alphabetically by Swift Charts.
    static let seriesPalette: [Color] = [
        accent,
        adaptive(dark: (0.290, 0.757, 0.706), light: (0.106, 0.549, 0.510)),   // teal
        warning,
        adaptive(dark: (0.663, 0.573, 0.965), light: (0.435, 0.318, 0.816)),   // violet
        adaptive(dark: (0.400, 0.788, 0.451), light: (0.180, 0.573, 0.267)),   // green
        adaptive(dark: (0.918, 0.443, 0.667), light: (0.769, 0.192, 0.478)),   // pink
    ]

    /// Everything past the palette is lumped together under one neutral, so the chart's
    /// colour domain and range always have the same size — mismatched, Swift Charts
    /// silently gives two series the same colour.
    static let overflowSeriesColor = adaptive(dark: (0.60, 0.60, 0.63), light: (0.42, 0.42, 0.45))

    private static func adaptive(
        dark: (Double, Double, Double),
        light: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (red, green, blue) = isDark ? dark : light
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        })
    }
}

extension Text {
    /// Numbers that change every poll should not make the layout jitter.
    func numeric() -> Text { self.monospacedDigit() }
}
