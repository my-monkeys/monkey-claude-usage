import Foundation

/// Tokens billed in one quarter-hour slot, split by model.
///
/// Quarter-hour is the finest bucket the UI ever needs (a six-hour range shows 24 bars),
/// and every coarser bucket is a sum of these — so the cache is written once and every
/// range is derived from it.
public struct ActivitySlot: Codable, Sendable, Equatable {
    public let start: Date
    public var byModel: [String: TokenCounts]

    public init(start: Date, byModel: [String: TokenCounts] = [:]) {
        self.start = start
        self.byModel = byModel
    }

    public var total: TokenCounts {
        byModel.values.reduce(into: TokenCounts()) { $0.add($1) }
    }
}

public struct TokenCounts: Codable, Sendable, Equatable {
    public var input = 0
    public var output = 0
    public var cacheCreation = 0
    public var cacheRead = 0

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public var total: Int { input + output + cacheCreation + cacheRead }

    public mutating func add(_ other: TokenCounts) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

/// How a bar's height is measured. Cache reads dwarf everything else, so the honest
/// default has to say which number it is showing.
public enum ActivityMeasure: String, CaseIterable, Sendable {
    case allTokens, output

    public var titleKey: String {
        switch self {
        case .allTokens: "measure_all_tokens"
        case .output: "measure_output"
        }
    }

    public func value(of counts: TokenCounts) -> Int {
        switch self {
        case .allTokens: counts.total
        case .output: counts.output
        }
    }
}

/// A bucket as the chart wants it: a start, a width, and tokens per model.
public struct ActivityBucket: Identifiable, Sendable, Equatable {
    public let start: Date
    public let byModel: [String: Int]

    public var id: Date { start }
    public var total: Int { byModel.values.reduce(0, +) }
}

extension Collection where Element == ActivitySlot {
    /// Rolls quarter-hour slots up into buckets of `width`, keeping empty buckets so the
    /// chart shows the gaps instead of closing them up.
    public func buckets(
        width: TimeInterval,
        since: Date,
        until: Date,
        measure: ActivityMeasure,
        calendar: Calendar = .current
    ) -> [ActivityBucket] {
        let origin = floor(since.timeIntervalSince1970 / width) * width
        var totals: [Int: [String: Int]] = [:]

        for slot in self where slot.start >= since && slot.start < until {
            let index = Int((slot.start.timeIntervalSince1970 - origin) / width)
            for (model, counts) in slot.byModel {
                let value = measure.value(of: counts)
                guard value > 0 else { continue }
                totals[index, default: [:]][model, default: 0] += value
            }
        }

        let count = Swift.max(1, Int(ceil((until.timeIntervalSince1970 - origin) / width)))
        return (0..<count).map { index in
            ActivityBucket(
                start: Date(timeIntervalSince1970: origin + Double(index) * width),
                byModel: totals[index] ?? [:]
            )
        }
    }
}
