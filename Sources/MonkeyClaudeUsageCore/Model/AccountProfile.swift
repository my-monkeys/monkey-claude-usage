import Foundation

/// `GET /api/oauth/profile` — who the token belongs to.
///
/// Its `account.uuid` is what tells two accounts apart: e-mail addresses can be edited
/// and display names collide, but this identifier is stable for the life of the account.
public struct AccountProfile: Decodable, Sendable, Equatable {
    public let account: AccountInfo?
    public let organization: OrganizationInfo?

    public struct AccountInfo: Decodable, Sendable, Equatable {
        public let uuid: String?
        public let email: String?
        public let displayName: String?
        public let fullName: String?
        public let hasClaudeMax: Bool?
        public let hasClaudePro: Bool?

        enum CodingKeys: String, CodingKey {
            case uuid, email
            case displayName = "display_name"
            case fullName = "full_name"
            case hasClaudeMax = "has_claude_max"
            case hasClaudePro = "has_claude_pro"
        }
    }

    public struct OrganizationInfo: Decodable, Sendable, Equatable {
        public let organizationType: String?
        public let rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case organizationType = "organization_type"
            case rateLimitTier = "rate_limit_tier"
        }
    }

    public var remoteID: String? { account?.uuid }
    public var email: String? { account?.email.flatMap { $0.isEmpty ? nil : $0 } }
    public var name: String? {
        [account?.displayName, account?.fullName].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// "Max 20×", "Pro", or whatever the organization calls itself — shown next to the
    /// account so the limits have a scale attached.
    public var planLabel: String? {
        if account?.hasClaudeMax == true {
            let multiplier = organization?.rateLimitTier
                .flatMap { tier in tier.split(separator: "_").last { $0.hasSuffix("x") } }
                .map { $0.replacingOccurrences(of: "x", with: "×") }
            return multiplier.map { "Max \($0)" } ?? "Max"
        }
        if account?.hasClaudePro == true { return "Pro" }
        return organization?.organizationType?
            .replacingOccurrences(of: "claude_", with: "")
            .capitalized
    }
}
