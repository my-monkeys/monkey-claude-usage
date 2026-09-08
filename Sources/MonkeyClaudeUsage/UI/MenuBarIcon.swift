import AppKit
import MonkeyClaudeUsageCore

public enum MenuBarStyle: String, CaseIterable, Sendable {
    case bars, logo, both

    var titleKey: String {
        switch self {
        case .bars: "style_bars"
        case .logo: "style_logo"
        case .both: "style_both"
        }
    }
}

/// What the menu bar needs to know about one account — no Combine, no service.
struct MenuBarAccount {
    let tag: String
    let limits: [UsageLimit]

    /// A saturated limit makes its bar useless: it is pinned at 100 % until the window
    /// rolls over, so the block switches to a countdown instead.
    var blockingLimit: UsageLimit? {
        limits
            .filter(\.isSaturated)
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

private enum Metrics {
    static let height: CGFloat = 18
    static let labelWidth: CGFloat = 12
    static let tagWidth: CGFloat = 8
    static let innerGap: CGFloat = 2
    static let accountGap: CGFloat = 6
    static let corner: CGFloat = 2
    static let logoSize: CGFloat = 14
    static let logoGap: CGFloat = 4
    static let labelFontSize: CGFloat = 7
    static let countdownFontSize: CGFloat = 8

    static func rowGeometry(rowCount: Int) -> (bar: CGFloat, gap: CGFloat) {
        switch rowCount {
        case 0, 1: (5, 0)
        case 2: (4, 2.5)
        case 3: (3.5, 2)
        default: (3, 1.5)
        }
    }
}

/// A row is one limit, shared across accounts so their bars line up vertically.
private struct Row {
    let id: String
    let label: String
}

func renderMenuBarIcon(
    accounts: [MenuBarAccount],
    style: MenuBarStyle,
    compact: Bool
) -> NSImage {
    let barWidth: CGFloat = compact ? 16 : 22
    let showLogo = style != .bars
    let showBars = style != .logo

    guard showBars, !accounts.isEmpty else {
        return image(width: Metrics.logoSize + 2) { drawLogo(x: 1, y: (Metrics.height - Metrics.logoSize) / 2) }
    }

    let rows = rowsFor(accounts)
    guard !rows.isEmpty else {
        return renderPlaceholderIcon(style: style, compact: compact)
    }

    // A single account can afford explicit row labels; several accounts need the
    // horizontal room for a per-account tag instead, and rely on a fixed row order.
    let usesRowLabels = accounts.count == 1
    let blocks = accounts.map { blockWidth(for: $0, rows: rows, barWidth: barWidth, usesRowLabels: usesRowLabels) }
    let logoWidth = showLogo ? Metrics.logoSize + Metrics.logoGap : 0
    let leadingLabels = usesRowLabels ? Metrics.labelWidth + Metrics.innerGap : 0
    let totalWidth = logoWidth + leadingLabels
        + blocks.reduce(0, +)
        + CGFloat(max(0, accounts.count - 1)) * Metrics.accountGap

    return image(width: totalWidth) {
        var x: CGFloat = 0
        if showLogo {
            drawLogo(x: 0, y: (Metrics.height - Metrics.logoSize) / 2)
            x += logoWidth
        }

        let geometry = Metrics.rowGeometry(rowCount: rows.count)
        let stackHeight = CGFloat(rows.count) * geometry.bar + CGFloat(rows.count - 1) * geometry.gap
        let top = (Metrics.height - stackHeight) / 2

        if usesRowLabels {
            for (index, row) in rows.enumerated() {
                let y = top + CGFloat(index) * (geometry.bar + geometry.gap)
                drawLabel(row.label, x: x, y: y, width: Metrics.labelWidth, rowHeight: geometry.bar)
            }
            x += Metrics.labelWidth + Metrics.innerGap
        }

        for (index, account) in accounts.enumerated() {
            if !usesRowLabels {
                drawLabel(account.tag, x: x, y: 0, width: Metrics.tagWidth, rowHeight: Metrics.height, centered: true)
                x += Metrics.tagWidth + Metrics.innerGap
            }

            if let blocking = account.blockingLimit {
                drawCountdown(for: blocking, x: x)
            } else {
                for (rowIndex, row) in rows.enumerated() {
                    let y = top + CGFloat(rowIndex) * (geometry.bar + geometry.gap)
                    if let limit = account.limits.first(where: { $0.id == row.id }) {
                        drawBar(x: x, y: y, width: barWidth, height: geometry.bar, fraction: limit.fraction)
                    } else {
                        drawDashedBar(x: x, y: y, width: barWidth, height: geometry.bar)
                    }
                }
            }

            x += blocks[index] - (usesRowLabels ? 0 : Metrics.tagWidth + Metrics.innerGap)
            x += Metrics.accountGap
        }
    }
}

/// Signed out, or signed in but nothing fetched yet.
func renderPlaceholderIcon(style: MenuBarStyle, compact: Bool) -> NSImage {
    let barWidth: CGFloat = compact ? 16 : 22
    let showLogo = style != .bars
    let showBars = style != .logo
    let logoWidth = showLogo ? Metrics.logoSize + Metrics.logoGap : 0
    let width = logoWidth + (showBars ? Metrics.labelWidth + Metrics.innerGap + barWidth : 0)

    return image(width: max(width, Metrics.logoSize + 2)) {
        if showLogo { drawLogo(x: 0, y: (Metrics.height - Metrics.logoSize) / 2) }
        guard showBars else { return }
        let geometry = Metrics.rowGeometry(rowCount: 2)
        let stackHeight = geometry.bar * 2 + geometry.gap
        let top = (Metrics.height - stackHeight) / 2
        for (index, label) in ["5h", "7d"].enumerated() {
            let y = top + CGFloat(index) * (geometry.bar + geometry.gap)
            drawLabel(label, x: logoWidth, y: y, width: Metrics.labelWidth, rowHeight: geometry.bar)
            drawDashedBar(x: logoWidth + Metrics.labelWidth + Metrics.innerGap, y: y, width: barWidth, height: geometry.bar)
        }
    }
}

// MARK: - Layout helpers

private func rowsFor(_ accounts: [MenuBarAccount]) -> [Row] {
    var seen: [String: UsageLimit] = [:]
    for account in accounts {
        for limit in account.limits where seen[limit.id] == nil {
            seen[limit.id] = limit
        }
    }
    return seen.values
        .sorted { $0.sortRank == $1.sortRank ? $0.id < $1.id : $0.sortRank < $1.sortRank }
        .map { Row(id: $0.id, label: $0.shortLabel) }
}

private func blockWidth(
    for account: MenuBarAccount,
    rows: [Row],
    barWidth: CGFloat,
    usesRowLabels: Bool
) -> CGFloat {
    let tag = usesRowLabels ? 0 : Metrics.tagWidth + Metrics.innerGap
    if let blocking = account.blockingLimit {
        return tag + countdownText(for: blocking).size().width
    }
    return tag + barWidth
}

private func countdownText(for limit: UsageLimit) -> NSAttributedString {
    let value = limit.resetsAt.map { Countdown.short(until: $0) } ?? "—"
    let font = NSFont.monospacedDigitSystemFont(ofSize: Metrics.countdownFontSize, weight: .semibold)
    return NSAttributedString(
        string: "\(limit.shortLabel) \(value)",
        attributes: [.font: font, .foregroundColor: NSColor.black]
    )
}

// MARK: - Drawing

private func image(width: CGFloat, _ draw: @escaping () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: max(width, 1), height: Metrics.height), flipped: true) { _ in
        draw()
        return true
    }
    image.isTemplate = true
    return image
}

private func drawLabel(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    rowHeight: CGFloat,
    centered: Bool = false
) {
    let font = NSFont.monospacedSystemFont(ofSize: Metrics.labelFontSize, weight: .medium)
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
    let size = string.size()
    let originX = centered ? x + (width - size.width) / 2 : x + width - size.width
    string.draw(at: NSPoint(x: originX, y: y + (rowHeight - size.height) / 2))
}

private func drawCountdown(for limit: UsageLimit, x: CGFloat) {
    let string = countdownText(for: limit)
    let size = string.size()
    string.draw(at: NSPoint(x: x, y: (Metrics.height - size.height) / 2))
}

private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fraction: Double) {
    let track = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height),
                             xRadius: Metrics.corner, yRadius: Metrics.corner)
    NSColor.black.withAlphaComponent(0.25).setFill()
    track.fill()

    guard fraction > 0 else { return }
    let filled = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width * fraction, height: height),
                              xRadius: Metrics.corner, yRadius: Metrics.corner)
    NSColor.black.setFill()
    filled.fill()
}

private func drawDashedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height),
                            xRadius: Metrics.corner, yRadius: Metrics.corner)
    NSColor.black.withAlphaComponent(0.3).setStroke()
    path.lineWidth = 1
    path.setLineDash([2, 2], count: 2, phase: 0)
    path.stroke()
}

private func drawLogo(x: CGFloat, y: CGFloat) {
    var transform = AffineTransform.identity
    transform.scale(Metrics.logoSize)
    transform.translate(x: x / Metrics.logoSize, y: y / Metrics.logoSize)
    guard let path = MonkeyGlyph.path.copy() as? NSBezierPath else { return }
    path.transform(using: transform)
    NSColor.black.setFill()
    path.fill()
}
