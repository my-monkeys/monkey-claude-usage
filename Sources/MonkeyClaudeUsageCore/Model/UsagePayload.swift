import Foundation

/// Decodes `/api/oauth/usage`.
///
/// Two shapes have to be supported: the current `limits` array, and the older fixed
/// fields still returned alongside it. The array wins when it carries anything, since
/// it is the only place model-scoped windows (Fable, Opus, Sonnet) appear.
struct UsagePayload: Decodable {
    let limits: [LimitEntry]?
    let fiveHour: LegacyBucket?
    let sevenDay: LegacyBucket?
    let sevenDayOpus: LegacyBucket?
    let sevenDaySonnet: LegacyBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    struct LimitEntry: Decodable {
        let kind: String
        let group: String?
        let percent: Double?
        let severity: String?
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?
        let lockedReason: String?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, severity, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
            case lockedReason = "locked_reason"
        }

        struct Scope: Decodable {
            let model: Model?
            let surface: Surface?

            struct Model: Decodable {
                let id: String?
                let displayName: String?
                enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
            }

            struct Surface: Decodable {
                let displayName: String?
                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }
        }
    }

    struct LegacyBucket: Decodable {
        let utilization: Double?
        let resetsAt: String?
        let lockedReason: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
            case lockedReason = "locked_reason"
        }
    }

    func snapshot(fetchedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(limits: buildLimits(), extraUsage: extraUsage, fetchedAt: fetchedAt)
    }

    private func buildLimits() -> [UsageLimit] {
        if let limits, !limits.isEmpty {
            return limits.map { entry in
                UsageLimit(
                    kind: entry.kind,
                    group: entry.group,
                    percent: entry.percent ?? 0,
                    severity: entry.severity,
                    resetsAt: ISO8601.date(from: entry.resetsAt),
                    modelName: entry.scope?.model?.displayName,
                    modelID: entry.scope?.model?.id,
                    surfaceName: entry.scope?.surface?.displayName,
                    isActive: entry.isActive ?? false,
                    lockedReason: entry.lockedReason
                )
            }
        }
        return legacyLimits()
    }

    private func legacyLimits() -> [UsageLimit] {
        var result: [UsageLimit] = []
        if let fiveHour, fiveHour.utilization != nil {
            result.append(legacy(fiveHour, kind: "session", group: "session"))
        }
        if let sevenDay, sevenDay.utilization != nil {
            result.append(legacy(sevenDay, kind: "weekly_all", group: "weekly"))
        }
        if let sevenDayOpus, sevenDayOpus.utilization != nil {
            result.append(legacy(sevenDayOpus, kind: "weekly_scoped", group: "weekly", model: "Opus"))
        }
        if let sevenDaySonnet, sevenDaySonnet.utilization != nil {
            result.append(legacy(sevenDaySonnet, kind: "weekly_scoped", group: "weekly", model: "Sonnet"))
        }
        return result
    }

    private func legacy(_ bucket: LegacyBucket, kind: String, group: String, model: String? = nil) -> UsageLimit {
        UsageLimit(
            kind: kind,
            group: group,
            percent: bucket.utilization ?? 0,
            resetsAt: ISO8601.date(from: bucket.resetsAt),
            modelName: model,
            lockedReason: bucket.lockedReason
        )
    }
}

/// The API returns six fractional digits (`…:00.435533+00:00`), which the strict
/// ISO-8601 parsers reject depending on the OS build — hence the truncating fallback.
public enum ISO8601 {
    /// Format styles rather than `ISO8601DateFormatter`: the latter wraps a
    /// `CFDateFormatter` that has to be allocated per use under strict concurrency, which
    /// costs tens of seconds across a hundred thousand transcript lines. These are values,
    /// `Sendable`, and built once.
    private static let styles = [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(),
    ]

    public static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        for style in styles {
            if let date = try? style.parse(value) { return date }
        }
        return date(fromTruncated: value)
    }

    private static func date(fromTruncated value: String) -> Date? {
        guard let dot = value.firstIndex(of: ".") else { return nil }
        let tail = value[dot...].dropFirst()
        guard let boundary = tail.firstIndex(where: { !$0.isNumber }) else { return nil }
        let truncated = String(value[..<dot] + tail[boundary...])
        return try? styles[1].parse(truncated)
    }
}
