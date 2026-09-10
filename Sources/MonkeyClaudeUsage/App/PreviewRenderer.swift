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
        // Both appearances, because a colour that reads on one can vanish on the other and
        // there is no way to tell without looking.
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            render(into: URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent(appearance == .darkAqua ? "dark" : "light"))
        }
    }

    private static func render(into directory: URL) {
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
            ("menubar-single-spent", renderMenuBarIcon(accounts: [secondSpent], style: .bars, compact: false)),
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

        renderPopovers(session: session, weekly: weekly, fable: fable, into: directory)
        renderActivity(into: directory)

        print("wrote \(cases.count + ChartRange.sessionCases.count + ChartRange.activityCases.count) previews to \(directory.path)")
    }

    /// The activity pane reads the transcripts of the Mac it runs on, so this preview
    /// shows real data rather than the synthetic history used for the quota chart.
    private static func renderActivity(into directory: URL) {
        let model = ActivityModel()
        model.load()

        // The first scan walks every transcript; give it room before capturing.
        let deadline = Date().addingTimeInterval(40)
        while model.slots.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }

        for range in ChartRange.activityCases {
            var value = range
            var measure = ActivityMeasure.allTokens
            let view = ActivityView(
                model: model,
                range: Binding(get: { value }, set: { value = $0 }),
                measure: Binding(get: { measure }, set: { measure = $0 })
            )
            .padding(14)
            .frame(width: Theme.popoverWidth)
            .background(Color(nsColor: .windowBackgroundColor))

            capture(view, to: directory.appendingPathComponent("activity-\(range.rawValue).png"))
        }
    }

    private static func capture(_ view: some View, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        hosting.layoutSubtreeIfNeeded()

        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }

    /// One image per range: a chart that reads well over six hours can be unreadable
    /// over thirty days, and the reverse.
    private static func renderPopovers(
        session: UsageLimit,
        weekly: UsageLimit,
        fable: UsageLimit,
        into directory: URL
    ) {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: PreferenceKey.chartRange)
        defer { defaults.set(previous, forKey: PreferenceKey.chartRange) }

        for range in ChartRange.sessionCases {
            defaults.set(range.rawValue, forKey: PreferenceKey.chartRange)
            var value = range
            let snapshot = UsageSnapshot(limits: [session, weekly, fable])
            capture(
                QuotaHistoryView(
                    limits: snapshot.limits,
                    samples: syntheticHistory(for: snapshot),
                    pollingMinutes: 15,
                    sessionRange: Binding(get: { value }, set: { value = $0 })
                )
                .padding(14)
                .frame(width: Theme.popoverWidth)
                .background(Color(nsColor: .windowBackgroundColor)),
                to: directory.appendingPathComponent("quota-\(range.rawValue).png")
            )
            renderPopover(
                session: session, weekly: weekly, fable: fable,
                to: directory.appendingPathComponent("popover-\(range.rawValue).png")
            )
        }
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
            PopoverView(state: state, activity: ActivityModel()).background(Color(nsColor: .windowBackgroundColor))
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

    /// Thirty days of quarter-hourly polling, so every range of the picker has data:
    /// the session window sawtooths every five hours, the weekly windows climb and drop
    /// on their own boundary, and the last one lands on the snapshot's own value.
    ///
    /// Deterministic on purpose — a preview that differs from one run to the next is
    /// useless for comparing two designs.
    private static func syntheticHistory(for snapshot: UsageSnapshot) -> [UsageSample] {
        let now = Date()
        let step: TimeInterval = 900
        let count = Int(30 * 86_400 / step)

        return (0..<count).map { index in
            let age = Double(count - 1 - index) * step
            let elapsed = Double(index) * step

            var values: [String: Double] = [:]
            for limit in snapshot.limits {
                let seed = Double(abs(limit.id.hashValue) % 97)
                values[limit.id] = utilisation(of: limit, elapsed: elapsed, age: age, seed: seed)
            }
            return UsageSample(date: now.addingTimeInterval(-age), values: values)
        }
    }

    private static func utilisation(
        of limit: UsageLimit,
        elapsed: TimeInterval,
        age: TimeInterval,
        seed: Double
    ) -> Double {
        let period: TimeInterval = limit.isSession ? 5 * 3600 : 7 * 86_400
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period

        // The window still running has to end on the value the snapshot reports.
        if age < period { return limit.percent * max(0, min(1, 1 - age / period)) }

        // A quota only ever climbs until its window rolls over, so the shape has to be
        // monotone inside a window — the burstiness goes into how steep it climbs, not
        // into dips that would read as phantom resets.
        let windowIndex = floor(elapsed / period)
        let daytime = 0.35 + 0.65 * max(0, sin(windowIndex * 0.7 + seed))
        let ceiling = 45 + seed.truncatingRemainder(dividingBy: 50)

        // The integral of a strictly positive burst rate: lumpy, but never decreasing,
        // so no bucket looks like a phantom reset.
        let rate = 14.0
        let amplitude = 0.9
        let climb = phase + amplitude * (1 - cos(rate * phase + seed)) / rate
        let full = 1 + amplitude * (1 - cos(rate + seed)) / rate
        return max(0, min(100, ceiling * (climb / full) * daytime * 1.6))
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
