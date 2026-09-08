import MonkeyClaudeUsageCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

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
        .frame(width: 420, height: 330)
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

            Picker(L("language"), selection: $language) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { value in
                    Text(value.label).tag(value.rawValue)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accounts: some View {
        VStack(spacing: 0) {
            List {
                ForEach(state.monitors) { monitor in
                    AccountRow(monitor: monitor) { label in
                        state.rename(monitor.id, to: label)
                    } onRemove: {
                        state.remove(monitor.id)
                    }
                }
                .onMove { state.move(fromOffsets: $0, toOffset: $1) }
            }

            Text(L("second_account_hint"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
    }
}

private struct AccountRow: View {
    @ObservedObject var monitor: AccountMonitor
    let onRename: (String) -> Void
    let onRemove: () -> Void

    @State private var label = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(monitor.account.tag)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                TextField(L("rename_account"), text: $label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { onRename(label) }
                if let email = monitor.account.email {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .onAppear { label = monitor.account.label }
    }
}
