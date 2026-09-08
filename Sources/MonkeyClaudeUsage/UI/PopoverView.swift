import MonkeyClaudeUsageCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState
    @StateObject private var activity = ActivityModel()
    @AppStorage(PreferenceKey.chartRange) private var storedRange = ChartRange.sixHours.rawValue
    @AppStorage(PreferenceKey.activityRange) private var storedActivityRange = ChartRange.week.rawValue
    @AppStorage(PreferenceKey.activityMeasure) private var storedMeasure = ActivityMeasure.allTokens.rawValue

    /// Ticks the relative dates ("resets in 2 h 10") without re-polling the API.
    @State private var now = Date()
    @State private var isAddingAccount = false
    @State private var accountPendingRemoval: Account?
    @State private var accountBeingRenamed: Account?
    @State private var draftName = ""
    @State private var showsActivity = false

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBar

            if state.hasAccounts { accountTabs }

            if !state.hasAccounts || isAddingAccount || state.pendingAuthorization != nil {
                SignInView(state: state, isFirstAccount: !state.hasAccounts)
                    .onChange(of: state.signInRevision) { isAddingAccount = false }
            } else if showsActivity {
                ActivityView(model: activity, range: activityRange, measure: measure)
            } else if let monitor = state.selectedMonitor {
                AccountUsageView(
                    monitor: monitor,
                    now: now,
                    sessionRange: chartRange,
                    pollingMinutes: state.pollingMinutes,
                    onReauthorize: { isAddingAccount = true }
                )
            }

            footer
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .onReceive(clock) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .openSignIn)) { _ in
            isAddingAccount = true
        }
        .alert(L("rename_account"), isPresented: Binding(
            get: { accountBeingRenamed != nil },
            set: { if !$0 { accountBeingRenamed = nil } }
        )) {
            TextField(L("rename_account"), text: $draftName)
            Button(L("validate")) {
                if let account = accountBeingRenamed {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { state.rename(account.id, to: trimmed) }
                }
                accountBeingRenamed = nil
            }
            Button(L("cancel"), role: .cancel) { accountBeingRenamed = nil }
        } message: {
            if let email = accountBeingRenamed?.email { Text(email) }
        }
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

    private func isAmbiguous(_ monitor: AccountMonitor) -> Bool {
        state.monitors.filter { $0.account.displayName == monitor.account.displayName }.count > 1
    }

    private var chartRange: Binding<ChartRange> {
        Binding(
            get: { ChartRange(rawValue: storedRange) ?? .sixHours },
            set: { storedRange = $0.rawValue }
        )
    }

    private var activityRange: Binding<ChartRange> {
        Binding(
            get: { ChartRange(rawValue: storedActivityRange) ?? .week },
            set: { storedActivityRange = $0.rawValue }
        )
    }

    private var measure: Binding<ActivityMeasure> {
        Binding(
            get: { ActivityMeasure(rawValue: storedMeasure) ?? .allTokens },
            set: { storedMeasure = $0.rawValue }
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
                    tag: state.menuBarTag(for: monitor.id),
                    ambiguous: isAmbiguous(monitor)
                ) {
                    isAddingAccount = false
                    showsActivity = false
                    state.cancelSignIn()
                    state.select(monitor.id)
                }
                .contextMenu {
                    Button(L("rename_account")) {
                        draftName = monitor.account.label
                        accountBeingRenamed = monitor.account
                    }
                    Button(L("remove_account"), role: .destructive) {
                        accountPendingRemoval = monitor.account
                    }
                }
            }

            Button {
                isAddingAccount = true
                showsActivity = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .help(L("add_account"))

            Spacer(minLength: 0)

            // Sits apart from the account tabs on purpose: what it shows belongs to the
            // machine, not to an account.
            Button {
                showsActivity.toggle()
                isAddingAccount = false
            } label: {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11, weight: showsActivity ? .semibold : .regular))
                    .frame(width: 24, height: 22)
                    .glassChip(isProminent: showsActivity)
                    .opacity(showsActivity ? 1 : 0.72)
            }
            .buttonStyle(.plain)
            .help(L("activity"))
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
    let tag: String
    /// Two accounts can carry the same name — the profile endpoint names both of them
    /// after the same person — so the tab then shows the menu bar tag to tell them apart.
    let ambiguous: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if ambiguous {
                    Text(tag)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
            .glassChip(isProminent: isSelected)
            .opacity(isSelected ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .help([monitor.account.email, monitor.account.plan].compactMap { $0 }.joined(separator: " · "))
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("fr.mymonkey.monkeyclaudeusage.openSettings")
    /// Posted by Settings so the popover shows the code field for a sign-in it started.
    static let openSignIn = Notification.Name("fr.mymonkey.monkeyclaudeusage.openSignIn")
}
