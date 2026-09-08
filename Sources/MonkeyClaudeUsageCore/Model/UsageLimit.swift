import Foundation

/// One rate-limit window returned by `/api/oauth/usage`.
///
/// Anthropic moved from fixed fields (`five_hour`, `seven_day_opus`, …) to a generic
/// `limits` array whose entries carry their own scope. Model-scoped weekly limits —
/// Fable, Opus, Sonnet — only exist in that array, which is why this type mirrors it
/// rather than the legacy shape.
public struct UsageLimit: Codable, Sendable, Equatable, Identifiable {
    public let kind: String
    public let group: String?
    public let percent: Double
    public let severity: String?
    public let resetsAt: Date?
    public let modelName: String?
    /// Kept even though the UI shows `modelName`: the API nulls one of the two, and two
    /// windows that both arrive without a display name would otherwise share an id.
    public let modelID: String?
    public let surfaceName: String?
    public let isActive: Bool
    public let lockedReason: String?

    public init(
        kind: String,
        group: String? = nil,
        percent: Double,
        severity: String? = nil,
        resetsAt: Date? = nil,
        modelName: String? = nil,
        modelID: String? = nil,
        surfaceName: String? = nil,
        isActive: Bool = false,
        lockedReason: String? = nil
    ) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.modelName = modelName
        self.modelID = modelID
        self.surfaceName = surfaceName
        self.isActive = isActive
        self.lockedReason = lockedReason
    }

    /// Stable across polls, so history series and menu bar rows keep their identity.
    public var id: String {
        [kind, modelName ?? modelID ?? "", surfaceName ?? ""].joined(separator: "|")
    }

    public var fraction: Double { max(0, min(1, percent / 100)) }

    public var isSaturated: Bool { percent >= 100 || lockedReason != nil }

    public var isSession: Bool { kind == "session" || group == "session" }

    /// Two characters at most — the menu bar has no room for more.
    public var shortLabel: String {
        if let modelName, !modelName.isEmpty {
            return String(modelName.prefix(2))
        }
        if isSession { return "5h" }
        return "7d"
    }

    /// Sorts session first, then the all-model weekly window, then per-model windows.
    public var sortRank: Int {
        if isSession { return 0 }
        if modelName == nil { return 1 }
        return 2
    }
}

/// A full reading of the usage endpoint at one point in time.
public struct UsageSnapshot: Sendable, Equatable {
    public let limits: [UsageLimit]
    public let extraUsage: ExtraUsage?
    public let fetchedAt: Date

    public init(limits: [UsageLimit], extraUsage: ExtraUsage? = nil, fetchedAt: Date = Date()) {
        self.limits = limits.sorted { lhs, rhs in
            lhs.sortRank == rhs.sortRank ? lhs.id < rhs.id : lhs.sortRank < rhs.sortRank
        }
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }

    public var saturatedLimits: [UsageLimit] { limits.filter(\.isSaturated) }

    public var nextRelease: UsageLimit? { limits.firstToRelease }
}

extension Collection where Element == UsageLimit {
    /// The spent window that frees up first — what the menu bar counts down to. A window
    /// with no reset date loses to one that has a date, and only wins if nothing else is
    /// spent.
    public var firstToRelease: UsageLimit? {
        let spent = filter(\.isSaturated)
        return spent
            .filter { $0.resetsAt != nil }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
            ?? spent.first
    }
}

public struct ExtraUsage: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let utilization: Double?
    public let usedCredits: Double?
    public let monthlyLimit: Double?
    public let currency: String?
    public let decimalPlaces: Int?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case currency
        case decimalPlaces = "decimal_places"
    }

    private var divisor: Double { pow(10, Double(decimalPlaces ?? 2)) }

    public var usedAmount: Double? { usedCredits.map { $0 / divisor } }
    public var limitAmount: Double? { monthlyLimit.map { $0 / divisor } }

    public func formatted(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}
