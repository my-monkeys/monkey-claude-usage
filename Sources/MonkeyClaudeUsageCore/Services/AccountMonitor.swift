import Combine
import Foundation

/// Watches one account: refreshes its token, polls the usage endpoint, and keeps the
/// sampled history that feeds the chart.
@MainActor
public final class AccountMonitor: ObservableObject, Identifiable {
    public enum State: Equatable, Sendable {
        case ready
        case expired
        case failing(String)
    }

    public nonisolated var id: UUID { accountID }

    @Published public private(set) var account: Account
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var history: [UsageSample] = []
    @Published public private(set) var state: State = .ready
    @Published public private(set) var lastUpdated: Date?

    public let accountID: UUID

    private let client: OAuthClient
    private let keychain: Keychain
    private let historyStore: UsageHistoryStore
    private var backoffUntil: Date?
    private var isRefreshing = false
    /// A refresh suspended on the network resumes *after* `forget()`, and would happily
    /// write a fresh token back for an account the user has removed.
    private var isForgotten = false

    public init(
        account: Account,
        client: OAuthClient = OAuthClient(),
        keychain: Keychain = Keychain(),
        historyStore: UsageHistoryStore
    ) {
        self.account = account
        self.accountID = account.id
        self.client = client
        self.keychain = keychain
        self.historyStore = historyStore
    }

    /// Read at each write rather than cached, so lowering the retention in Settings
    /// prunes on the next poll instead of at the next launch.
    private var retentionDays: Int {
        let stored = UserDefaults.standard.integer(forKey: PreferenceKey.retentionDays)
        return stored > 0 ? stored : UsageHistoryStore.defaultRetentionDays
    }

    /// Fully-formed monitor with no network behind it — SwiftUI previews and the
    /// documentation screenshots.
    public static func preview(
        account: Account,
        snapshot: UsageSnapshot,
        history: [UsageSample] = [],
        lastUpdated: Date = Date()
    ) -> AccountMonitor {
        let monitor = AccountMonitor(account: account, historyStore: UsageHistoryStore())
        monitor.snapshot = snapshot
        monitor.history = history
        monitor.lastUpdated = lastUpdated
        return monitor
    }

    public func loadHistory() async {
        history = await historyStore.load(accountID)
    }

    public func rename(_ label: String) {
        account.label = label
        account.hasCustomLabel = true
    }

    /// - Parameter force: ignore the rate-limit backoff (user tapped refresh).
    public func refresh(force: Bool = false) async {
        if !force, let backoffUntil, backoffUntil > Date() { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard var token = await validAccessToken() else { return }

        do {
            var result = try await client.fetchUsage(token: token)

            if result.statusCode == 401 {
                guard let renewed = await forceRefreshToken() else { return }
                token = renewed
                result = try await client.fetchUsage(token: token)
                if result.statusCode == 401 {
                    state = .expired
                    return
                }
            }

            if result.statusCode == 429 {
                backoffUntil = Date().addingTimeInterval(result.retryAfter ?? 600)
                state = .failing(CoreStrings.rateLimited)
                return
            }

            guard result.statusCode == 200 else {
                state = .failing("HTTP \(result.statusCode)")
                return
            }

            guard !isForgotten else { return }

            let payload = try JSONDecoder().decode(UsagePayload.self, from: result.data)
            let fresh = payload.snapshot()
            snapshot = fresh
            lastUpdated = fresh.fetchedAt
            state = .ready
            backoffUntil = nil
            history = await historyStore.append(
                UsageSample(snapshot: fresh),
                for: accountID,
                retentionDays: retentionDays
            )

            if account.remoteID == nil { await fetchProfile(token: token) }
        } catch {
            state = .failing(error.localizedDescription)
        }
    }

    /// Synchronous flag first: everything after this point must refuse to write.
    public func forget() {
        isForgotten = true
        keychain.delete(accountID)
        Task { [historyStore, accountID] in await historyStore.delete(accountID) }
    }

    // MARK: - Token plumbing

    private func validAccessToken() async -> String? {
        guard let credentials = keychain.load(accountID) else {
            state = .expired
            return nil
        }
        guard credentials.needsRefresh() else { return credentials.accessToken }
        if let renewed = await forceRefreshToken() { return renewed }
        return credentials.isExpired() ? nil : credentials.accessToken
    }

    private func forceRefreshToken() async -> String? {
        guard let credentials = keychain.load(accountID) else {
            state = .expired
            return nil
        }
        do {
            let renewed = try await client.refresh(credentials)
            guard !isForgotten else { return nil }
            try keychain.save(renewed, for: accountID)
            return renewed.accessToken
        } catch let error as OAuthError where error.isPermanent {
            state = .expired
            return nil
        } catch {
            state = .failing(error.localizedDescription)
            return nil
        }
    }

    private func fetchProfile(token: String) async {
        guard let profile = try? await client.fetchProfile(token: token) else { return }
        account.remoteID = profile.remoteID ?? account.remoteID
        account.email = profile.email ?? account.email
        account.plan = profile.planLabel ?? account.plan
        // `label` is never empty — creation gives it a "Account 2" placeholder — so the
        // question is whether the user has since chosen a name of their own.
        if !account.hasCustomLabel, let name = profile.name ?? profile.email {
            account.label = name
        }
    }
}
