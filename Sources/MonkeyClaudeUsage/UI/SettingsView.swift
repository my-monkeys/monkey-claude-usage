import MonkeyClaudeUsageCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var updater: Updater

    @AppStorage(PreferenceKey.language) private var language = AppLanguage.system.rawValue
    @AppStorage(PreferenceKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.bars.rawValue
    @AppStorage(PreferenceKey.compactMenuBar) private var compact = false
    @AppStorage(PreferenceKey.notificationsEnabled) private var notifications = true
    @AppStorage(PreferenceKey.retentionDays) private var retentionDays = UsageHistoryStore.defaultRetentionDays

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            general.tabItem { Label(L("settings"), systemImage: "gearshape") }
            accounts.tabItem { Label(L("accounts"), systemImage: "person.2") }
        }
        // Must match the window in AppDelegate.openSettings.
        .frame(width: 420, height: 400)
    }

    private var general: some View {
        Form {
            Picker(L("polling_interval"), selection: $state.pollingMinutes) {
                ForEach(AppState.pollingOptions, id: \.self) { minutes in
                    Text(L("minutes", minutes)).tag(minutes)
                }
            }

            Picker(L("menu_bar"), selection: $menuBarStyle) {
                ForEach(MenuBarStyle.allCases, id: \.rawValue) { style in
                    Text(L(style.titleKey)).tag(style.rawValue)
                }
            }

            Toggle(L("compact"), isOn: $compact)

            Picker(L("retention"), selection: $retentionDays) {
                ForEach([7, 30, 90], id: \.self) { days in
                    Text(L("days", days)).tag(days)
                }
            }

            Divider()

            Toggle(L("notifications"), isOn: $notifications)

            Toggle(L("launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }

            Toggle(L("automatic_updates"), isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))

            Picker(L("language"), selection: $language) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { value in
                    Text(value.label).tag(value.rawValue)
                }
            }

            if let version = Updater.displayedVersion {
                Text(L("version", version))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private var accounts: some View {
        VStack(spacing: 0) {
            List {
                ForEach(state.monitors) { monitor in
                    AccountRow(
                        monitor: monitor,
                        badge: state.menuBarBadge(for: monitor.id),
                        isCustomBadge: monitor.account.badge != nil,
                        onRename: { state.rename(monitor.id, to: $0) },
                        onBadge: { state.setBadge($0, for: monitor.id) },
                        onRemove: { state.remove(monitor.id) }
                    )
                }
                .onMove { state.move(fromOffsets: $0, toOffset: $1) }
            }

            HStack(spacing: 8) {
                // Only asks the popover to show its sign-in pane. Starting the browser
                // flow here would leave the pasted-back code with nowhere to go: the field
                // that receives it lives in the popover.
                Button {
                    NotificationCenter.default.post(name: .openSignIn, object: nil)
                } label: {
                    Label(L("add_account"), systemImage: "plus")
                }
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Text(L("second_account_hint"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}

private struct AccountRow: View {
    @ObservedObject var monitor: AccountMonitor
    let badge: AccountBadge
    /// Whether the badge shown is the user's own choice or the automatic fallback.
    let isCustomBadge: Bool
    let onRename: (String) -> Void
    let onBadge: (AccountBadge?) -> Void
    let onRemove: () -> Void

    @State private var label = ""
    @State private var letters = ""
    @State private var isPickingBadge = false
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 10) {
            badgePicker

            VStack(alignment: .leading, spacing: 2) {
                TextField(L("rename_account"), text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($isEditing)
                    .onSubmit(commit)

                if let email = monitor.account.email {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            if let plan = monitor.account.plan {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .glassChip(cornerRadius: 8)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .onAppear {
            label = monitor.account.label
            letters = lettersFromBadge
        }
        // The label arrives with the profile, often after this row is on screen; without
        // this, submitting the field would write the stale placeholder back.
        .onChange(of: monitor.account.label) { _, new in
            if !isEditing { label = new }
        }
        // Clicking away is as much a commit as pressing return.
        .onChange(of: isEditing) { wasEditing, _ in
            if wasEditing { commit() }
        }
    }

    /// A popover rather than a menu: the choice is visual, and a menu would list twelve
    /// entries whose labels all read "Symbol".
    private var badgePicker: some View {
        Button { isPickingBadge = true } label: {
            BadgeView(badge: badge)
                .frame(width: 24, height: 22)
                .foregroundStyle(isCustomBadge ? .primary : .secondary)
                .glassChip(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .help(L("menu_bar_tag_help"))
        .popover(isPresented: $isPickingBadge, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("badge_help"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 210, alignment: .leading)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 6), spacing: 6) {
                    ForEach(AccountBadge.offered, id: \.self) { name in
                        Button {
                            letters = ""
                            onBadge(.symbol(name))
                            isPickingBadge = false
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 12))
                                .frame(width: 26, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(badge == .symbol(name)
                                              ? Theme.accent.opacity(0.22)
                                              : Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    // Two characters at most: past that the menu bar has no room.
                    TextField(L("badge_letters"), text: $letters)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 62)
                        .onChange(of: letters) { _, new in
                            let trimmed = String(new.prefix(2))
                            if trimmed != new { letters = trimmed }
                        }
                        .onSubmit(commitLetters)

                    Button(L("badge_automatic")) {
                        letters = ""
                        onBadge(nil)
                        isPickingBadge = false
                    }
                    .controlSize(.small)
                    .disabled(!isCustomBadge)

                    Spacer()
                }
            }
            .padding(12)
            .onDisappear(perform: commitLetters)
        }
    }

    private func commitLetters() {
        let trimmed = letters.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard badge != .text(trimmed) || !isCustomBadge else { return }
        onBadge(.text(trimmed))
    }

    private var lettersFromBadge: String {
        if case let .text(value) = badge, isCustomBadge { return value }
        return ""
    }

    private func commit() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != monitor.account.label else {
            label = monitor.account.label
            return
        }
        onRename(trimmed)
    }
}
