import Combine
import Foundation

/// Owns the account list, the shared poll timer and the pending sign-in flow.
@MainActor
public final class AppState: ObservableObject {
    public static let pollingOptions = [5, 10, 15, 30, 60]
    public static let defaultPollingMinutes = 15

    @Published public private(set) var monitors: [AccountMonitor] = []
    @Published public var selectedAccountID: UUID?
    @Published public private(set) var pendingAuthorization: OAuthClient.PendingAuthorization?
    @Published public private(set) var isExchangingCode = false
    @Published public private(set) var authorizationError: String?
    /// Bumped whenever a sign-in finishes, added account or not — re-authorizing an
    /// existing account leaves `monitors.count` untouched, so the popover would stay
    /// stuck on its sign-in screen if it watched the count.
    @Published public private(set) var signInRevision = 0
    @Published public var pollingMinutes: Int {
        didSet {
            UserDefaults.standard.set(pollingMinutes, forKey: PreferenceKey.pollingMinutes)
            scheduleTimer()
        }
    }

    private let client: OAuthClient
    private let keychain: Keychain
    private let historyStore: UsageHistoryStore
    private let defaults: UserDefaults
    private var timer: Timer?
    private var observations: [UUID: AnyCancellable] = [:]

    public init(
        client: OAuthClient = OAuthClient(),
        keychain: Keychain = Keychain(),
        historyStore: UsageHistoryStore = UsageHistoryStore(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.keychain = keychain
        self.historyStore = historyStore
        self.defaults = defaults

        let stored = defaults.integer(forKey: PreferenceKey.pollingMinutes)
        self.pollingMinutes = Self.pollingOptions.contains(stored) ? stored : Self.defaultPollingMinutes

        loadAccounts()
        if let raw = defaults.string(forKey: PreferenceKey.selectedAccount) {
            selectedAccountID = UUID(uuidString: raw)
        }
        if selectedAccountID == nil || !monitors.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = monitors.first?.id
        }
    }

    public static func preview(monitors: [AccountMonitor]) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: "preview") ?? .standard)
        state.monitors = monitors
        state.selectedAccountID = monitors.first?.id
        return state
    }

    public var selectedMonitor: AccountMonitor? {
        monitors.first { $0.id == selectedAccountID } ?? monitors.first
    }

    public var hasAccounts: Bool { !monitors.isEmpty }

    /// What marks an account in the menu bar. A badge the user chose wins outright;
    /// otherwise the first letter of the name, which is only useful while the letters
    /// differ — the profile endpoint names every account after the same person, so a
    /// collision demotes *every* account to its position number rather than mixing
    /// letters and digits.
    public func menuBarBadge(for accountID: UUID) -> AccountBadge {
        guard let index = monitors.firstIndex(where: { $0.id == accountID }) else {
            return .text("?")
        }
        if let chosen = AccountBadge(stored: monitors[index].account.badge) { return chosen }

        let automatic = monitors.map { AccountBadge(stored: $0.account.badge) }
        let initials = monitors.map(\.account.initial)
        let free = zip(automatic, initials).filter { $0.0 == nil }.map(\.1)
        return Set(free).count == free.count ? .text(initials[index]) : .text("\(index + 1)")
    }

    public func setBadge(_ badge: AccountBadge?, for accountID: UUID) {
        monitors.first { $0.id == accountID }?.setBadge(badge)
        persistAccounts()
    }

    public func start() {
        Task {
            for monitor in monitors { await monitor.loadHistory() }
            await refreshAll()
        }
        scheduleTimer()
    }

    public func select(_ accountID: UUID) {
        selectedAccountID = accountID
        defaults.set(accountID.uuidString, forKey: PreferenceKey.selectedAccount)
    }

    /// Sequential on purpose: a handful of accounts hitting the same rate-limited
    /// endpoint at the exact same instant buys nothing.
    public func refreshAll(force: Bool = false) async {
        for monitor in monitors {
            await monitor.refresh(force: force)
        }
    }

    // MARK: - Sign in

    /// - Returns: the URL the caller must open in the browser.
    public func beginSignIn() -> URL {
        let pending = client.beginAuthorization()
        pendingAuthorization = pending
        authorizationError = nil
        return pending.url
    }

    public func cancelSignIn() {
        pendingAuthorization = nil
        authorizationError = nil
    }

    public func completeSignIn(code: String) async {
        guard let pending = pendingAuthorization else { return }
        isExchangingCode = true
        defer { isExchangingCode = false }

        do {
            let credentials = try await client.exchange(pastedCode: code, pending: pending)
            let profile = try? await client.fetchProfile(token: credentials.accessToken)

            // The browser session decides which Claude account the code belongs to, so
            // "add an account" can very well hand back the one already added. Refresh
            // that account's tokens in place instead of opening a duplicate tab.
            if let existing = existingMonitor(matching: profile) {
                try keychain.save(credentials, for: existing.id)
                finishSignIn(selecting: existing.id)
                await existing.refresh(force: true)
                return
            }

            let account = Account(
                label: profile?.name ?? profile?.email ?? defaultLabel(),
                email: profile?.email,
                remoteID: profile?.remoteID,
                plan: profile?.planLabel
            )
            try keychain.save(credentials, for: account.id)
            let monitor = AccountMonitor(
                account: account,
                client: client,
                keychain: keychain,
                historyStore: historyStore
            )
            monitors.append(monitor)
            observe(monitor)
            persistAccounts()
            finishSignIn(selecting: account.id)
            await monitor.refresh(force: true)
            persistAccounts()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    /// Both criteria are tried, not one or the other: an account added while the profile
    /// endpoint was down has no `remoteID`, and matching on the new profile's id alone
    /// would then create a second tab for the same Claude account.
    private func existingMonitor(matching profile: AccountProfile?) -> AccountMonitor? {
        guard let profile else { return nil }
        return monitors.first { monitor in
            if let remoteID = profile.remoteID, monitor.account.remoteID == remoteID { return true }
            if let email = profile.email, monitor.account.email == email { return true }
            return false
        }
    }

    private func finishSignIn(selecting accountID: UUID) {
        pendingAuthorization = nil
        authorizationError = nil
        select(accountID)
        signInRevision += 1
    }

    // MARK: - Account management

    public func remove(_ accountID: UUID) {
        guard let index = monitors.firstIndex(where: { $0.id == accountID }) else { return }
        let monitor = monitors.remove(at: index)
        monitor.forget()
        observations[accountID] = nil
        persistAccounts()
        if selectedAccountID == accountID {
            selectedAccountID = monitors.first?.id
            defaults.set(selectedAccountID?.uuidString, forKey: PreferenceKey.selectedAccount)
        }
    }

    public func rename(_ accountID: UUID, to label: String) {
        monitors.first { $0.id == accountID }?.rename(label)
        persistAccounts()
    }

    /// SwiftUI's `move(fromOffsets:toOffset:)` lives in SwiftUI, which the core does
    /// not import — reordering is spelled out here instead.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moved = offsets.sorted().map { monitors[$0] }
        let insertion = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { monitors.remove(at: index) }
        monitors.insert(contentsOf: moved, at: max(0, min(insertion, monitors.count)))
        persistAccounts()
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = defaults.data(forKey: PreferenceKey.accounts),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else { return }
        monitors = accounts.map {
            AccountMonitor(account: $0, client: client, keychain: keychain, historyStore: historyStore)
        }
        monitors.forEach(observe)
    }

    private func persistAccounts() {
        let accounts = monitors.map(\.account)
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: PreferenceKey.accounts)
    }

    /// Account labels are filled in from the profile endpoint, which can change after
    /// the first poll — mirror that back into preferences, and republish so the menu
    /// bar redraws when any monitor changes.
    private func observe(_ monitor: AccountMonitor) {
        observations[monitor.id] = monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.persistAccounts()
            }
    }

    private func defaultLabel() -> String {
        let index = monitors.count + 1
        return AppLanguage.resolved == .fr ? "Compte \(index)" : "Account \(index)"
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(pollingMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
