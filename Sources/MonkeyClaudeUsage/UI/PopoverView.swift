import MonkeyClaudeUsageCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState
    @AppStorage(PreferenceKey.chartRange) private var storedRange = ChartRange.day.rawValue

    /// Ticks the relative dates ("resets in 2 h 10") without re-polling the API.
    @State private var now = Date()
    @State private var isAddingAccount = false
    @State private var accountPendingRemoval: Account?

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBar

            if state.hasAccounts { accountTabs }

            if !state.hasAccounts || isAddingAccount || state.pendingAuthorization != nil {
                SignInView(state: state, isFirstAccount: !state.hasAccounts)
                    .onChange(of: state.monitors.count) { isAddingAccount = false }
            } else if let monitor = state.selectedMonitor {
                AccountUsageView(
                    monitor: monitor,
                    now: now,
                    chartRange: chartRange,
                    onReauthorize: { isAddingAccount = true }
                )
            }

            footer
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .onReceive(clock) { now = $0 }
        .confirmationDialog(
            accountPendingRemoval.map { L("delete_confirm", $0.displayName) } ?? "",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            )
        ) {
            Button(L("remove"), role: .destructive) {
                if let account = accountPendingRemoval { state.remove(account.id) }
                accountPendingRemoval = nil
            }
            Button(L("cancel"), role: .cancel) { accountPendingRemoval = nil }
        }
    }

    private var chartRange: Binding<ChartRange> {
        Binding(
            get: { ChartRange(rawValue: storedRange) ?? .day },
            set: { storedRange = $0.rawValue }
        )
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(L("app_name"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await state.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L("refresh"))
            .disabled(!state.hasAccounts)
        }
    }

    private var accountTabs: some View {
        HStack(spacing: 4) {
            ForEach(state.monitors) { monitor in
                AccountTab(
                    monitor: monitor,
                    isSelected: !isAddingAccount && state.selectedAccountID == monitor.id,
                    now: now
                ) {
                    isAddingAccount = false
                    state.cancelSignIn()
                    state.select(monitor.id)
                }
                .contextMenu {
                    Button(L("remove_account"), role: .destructive) {
                        accountPendingRemoval = monitor.account
                    }
                }
            }

            Button {
                isAddingAccount = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .help(L("add_account"))

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button(L("settings")) {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button(L("quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccountTab: View {
    @ObservedObject var monitor: AccountMonitor
    let isSelected: Bool
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(monitor.account.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 118)
                    .fixedSize(horizontal: true, vertical: false)

                if let peak = monitor.snapshot?.limits.map(\.percent).max() {
                    Circle()
                        .fill(Theme.tint(for: peak))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("fr.mymonkey.monkeyclaudeusage.openSettings")
}
