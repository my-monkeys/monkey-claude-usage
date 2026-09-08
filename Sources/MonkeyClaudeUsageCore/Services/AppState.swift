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
    private var cancellables: Set<AnyCancellable> = []

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
                pendingAuthorization = nil
                await existing.refresh(force: true)
                select(existing.id)
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
            pendingAuthorization = nil
            select(account.id)
            await monitor.refresh(force: true)
            persistAccounts()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    private func existingMonitor(matching profile: AccountProfile?) -> AccountMonitor? {
        guard let profile else { return nil }
        if let remoteID = profile.remoteID {
            return monitors.first { $0.account.remoteID == remoteID }
        }
        guard let email = profile.email else { return nil }
        return monitors.first { $0.account.email == email }
    }

    /// Adopts the CLI's session as a new account. Returns false when there is nothing
    /// to import or when it turns out to be an account already present.
    @discardableResult
    public func importClaudeCodeSession() async -> Bool {
        guard let credentials = ClaudeCodeSession.read() else {
            authorizationError = L("import_failed")
            return false
        }

        let profile = try? await client.fetchProfile(token: credentials.accessToken)
        if let existing = existingMonitor(matching: profile) {
            try? keychain.save(credentials, for: existing.id)
            await existing.refresh(force: true)
            select(existing.id)
            return false
        }

        let account = Account(
            label: profile?.name ?? profile?.email ?? defaultLabel(),
            email: profile?.email,
            remoteID: profile?.remoteID,
            plan: profile?.planLabel
        )
        do {
            try keychain.save(credentials, for: account.id)
        } catch {
            authorizationError = error.localizedDescription
            return false
        }

        let monitor = AccountMonitor(
            account: account,
            client: client,
            keychain: keychain,
            historyStore: historyStore
        )
        monitors.append(monitor)
        observe(monitor)
        persistAccounts()
        select(account.id)
        await monitor.refresh(force: true)
        persistAccounts()
        return true
    }

    public var canImportClaudeCodeSession: Bool { ClaudeCodeSession.isAvailable }

    // MARK: - Account management

    public func remove(_ accountID: UUID) {
        guard let index = monitors.firstIndex(where: { $0.id == accountID }) else { return }
        let monitor = monitors.remove(at: index)
        Task { await monitor.forget() }
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
        monitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.persistAccounts()
            }
            .store(in: &cancellables)
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
