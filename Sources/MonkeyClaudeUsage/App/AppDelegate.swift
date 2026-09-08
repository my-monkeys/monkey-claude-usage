import AppKit
import MonkeyClaudeUsageCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let notifications = NotificationService()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var dismissMonitor: Any?
    private var redrawTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           let directory = CommandLine.arguments[safe: index + 1] {
            PreviewRenderer.run(outputDirectory: directory)
            NSApplication.shared.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: PopoverView(state: state))

        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings), name: .openSettings, object: nil
        )

        notifications.requestAuthorization()
        state.start()
        redraw()

        // The countdown shown when a limit is saturated has to keep ticking between polls.
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.redraw() }
        }
        RunLoop.main.add(timer, forMode: .common)
        redrawTimer = timer
    }

    // MARK: - Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
            return
        }
        popover.contentViewController?.view = NSHostingView(rootView: PopoverView(state: state))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(item(L("refresh"), #selector(refreshNow)))
        menu.addItem(item(L("settings"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("quit"), #selector(quit), key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        Task { await state.refreshAll(force: true) }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettings() {
        closePopover()

        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings")
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Menu bar drawing

    private func redraw() {
        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.menuBarStyle) ?? "")
            ?? .bars
        let compact = UserDefaults.standard.bool(forKey: PreferenceKey.compactMenuBar)

        let accounts = state.monitors.compactMap { monitor -> MenuBarAccount? in
            guard let snapshot = monitor.snapshot else { return nil }
            return MenuBarAccount(tag: monitor.account.tag, limits: snapshot.limits)
        }

        statusItem.button?.image = accounts.isEmpty
            ? renderPlaceholderIcon(style: style, compact: compact)
            : renderMenuBarIcon(accounts: accounts, style: style, compact: compact)
        statusItem.button?.toolTip = tooltip()

        for monitor in state.monitors {
            notifications.check(account: monitor.account, snapshot: monitor.snapshot)
        }
    }

    private func tooltip() -> String {
        state.monitors.compactMap { monitor -> String? in
            guard let snapshot = monitor.snapshot else { return nil }
            let detail = snapshot.limits
                .map { "\($0.shortLabel) \(Int($0.percent.rounded())) %" }
                .joined(separator: "  ·  ")
            return "\(monitor.account.displayName) — \(detail)"
        }
        .joined(separator: "\n")
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
