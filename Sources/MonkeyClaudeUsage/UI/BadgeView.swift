import MonkeyClaudeUsageCore
import SwiftUI

/// The account's menu bar badge, drawn the same way wherever it appears, so the popover
/// and Settings show exactly what the menu bar shows.
struct BadgeView: View {
    let badge: AccountBadge
    var size: CGFloat = 11

    var body: some View {
        switch badge {
        case let .text(value):
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size - 1, weight: .semibold))
        }
    }
}
