import Foundation

/// A Claude account the app watches. Tokens live in the keychain, keyed by `id`;
/// only this descriptor is stored in preferences.
public struct Account: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public var label: String
    public var email: String?
    /// `account.uuid` from the profile endpoint — how a re-authorization is recognised
    /// as being the same Claude account rather than a new one.
    public var remoteID: String?
    public var plan: String?

    public init(
        id: UUID = UUID(),
        label: String,
        email: String? = nil,
        remoteID: String? = nil,
        plan: String? = nil
    ) {
        self.id = id
        self.label = label
        self.email = email
        self.remoteID = remoteID
        self.plan = plan
    }

    /// Shown in the popover tabs.
    public var displayName: String {
        if !label.isEmpty { return label }
        if let email, !email.isEmpty { return email }
        return String(id.uuidString.prefix(4))
    }

    /// First letter of the name — only unique if the names are. `AppState.menuBarTag(for:)`
    /// is what the menu bar uses; it falls back to numbers when two accounts collide.
    public var initial: String {
        let source = label.isEmpty ? (email ?? "?") : label
        return String(source.prefix(1)).uppercased()
    }
}

public struct OAuthCredentials: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    public var canRefresh: Bool { !(refreshToken ?? "").isEmpty }

    public func needsRefresh(at now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        guard canRefresh, let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(leeway)
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}
