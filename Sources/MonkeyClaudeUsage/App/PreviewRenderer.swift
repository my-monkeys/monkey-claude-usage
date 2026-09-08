import AppKit
import MonkeyClaudeUsageCore
import SwiftUI

/// Renders the menu bar states to PNG files, so the layout can be inspected without
/// waiting for a real account to hit 100 %. Used to produce the README illustration:
///
///     "Monkey Claude Usage.app/Contents/MacOS/MonkeyClaudeUsage" --render-preview <dir>
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        let directory = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = Date()
        let session = UsageLimit(kind: "session", group: "session", percent: 31,
                                 resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60))
        let weekly = UsageLimit(kind: "weekly_all", group: "weekly", percent: 39,
                                resetsAt: now.addingTimeInterval(5 * 86_400))
        let fable = UsageLimit(kind: "weekly_scoped", group: "weekly", percent: 54,
                               resetsAt: now.addingTimeInterval(5 * 86_400),
                               modelName: "Fable", isActive: true)
        let spentSession = UsageLimit(kind: "session", group: "session", percent: 100,
                                      resetsAt: now.addingTimeInterval(3600 + 42 * 60))

        let first = MenuBarAccount(tag: "M", limits: [session, weekly, fable])
        let secondSpent = MenuBarAccount(tag: "P", limits: [spentSession, weekly, fable])

        let cases: [(String, NSImage)] = [
            ("menubar-single", renderMenuBarIcon(accounts: [first], style: .bars, compact: false)),
            ("menubar-single-logo", renderMenuBarIcon(accounts: [first], style: .both, compact: false)),
            ("menubar-two", renderMenuBarIcon(accounts: [first, MenuBarAccount(tag: "P", limits: [session, weekly, fable])],
                                              style: .bars, compact: false)),
            ("menubar-two-spent", renderMenuBarIcon(accounts: [first, secondSpent], style: .bars, compact: false)),
            ("menubar-compact", renderMenuBarIcon(accounts: [first, secondSpent], style: .bars, compact: true)),
            ("menubar-empty", renderPlaceholderIcon(style: .bars, compact: false)),
        ]

        for (name, image) in cases {
            write(image, to: directory.appendingPathComponent("\(name).png"))
        }

        renderPopover(session: session, weekly: weekly, fable: fable,
                      to: directory.appendingPathComponent("popover.png"))

        print("wrote \(cases.count + 1) previews to \(directory.path)")
    }

    private static func renderPopover(
        session: UsageLimit,
        weekly: UsageLimit,
        fable: UsageLimit,
        to url: URL
    ) {
        let snapshot = UsageSnapshot(limits: [session, weekly, fable])
        let state = AppState.preview(monitors: [
            AccountMonitor.preview(
                account: Account(label: "Maxim", email: "maxim@my-monkey.fr", plan: "Max 20×"),
                snapshot: snapshot,
                history: syntheticHistory(for: snapshot),
                lastUpdated: Date().addingTimeInterval(-180)
            ),
            AccountMonitor.preview(
                account: Account(label: "Perso", email: "perso@example.com", plan: "Pro"),
                snapshot: UsageSnapshot(limits: [session, weekly])
            ),
        ])

        // Rendered inside a real window: ImageRenderer draws buttons and pickers as
        // placeholder blocks, and a detached NSHostingView drops text altogether.
        let hosting = NSHostingView(rootView:
            PopoverView(state: state).background(Color(nsColor: .windowBackgroundColor))
        )
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()

        // Let SwiftUI and Swift Charts settle before the snapshot.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    /// A believable few hours of polling: usage climbs, with the session window
    /// resetting once along the way.
    private static func syntheticHistory(for snapshot: UsageSnapshot) -> [UsageSample] {
        let now = Date()
        return (0..<48).map { step in
            let age = Double(47 - step) * 300
            let progress = Double(step) / 47
            var values: [String: Double] = [:]
            for limit in snapshot.limits {
                let target = limit.percent
                let ramp = target * progress
                values[limit.id] = limit.isSession && step < 20
                    ? max(0, 88 * (Double(step) / 20))
                    : ramp
            }
            return UsageSample(date: now.addingTimeInterval(-age), values: values)
        }
    }

    /// Template images carry no colour; draw them onto a light background at 4× so the
    /// result is legible in a README rather than an invisible black-on-black strip.
    private static func write(_ image: NSImage, to url: URL) {
        let scale: CGFloat = 4
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
