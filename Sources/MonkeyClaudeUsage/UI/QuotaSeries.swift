import Foundation
import MonkeyClaudeUsageCore

/// Turns sampled levels into "points of quota burned per bucket".
///
/// A level that drops between two samples means the window rolled over, not a negative
/// consumption: what was billed before the reset is unknowable, so the bar for that bucket
/// is a floor and the boundary is marked.
struct ConsumptionSeries {
    struct Bucket: Identifiable {
        let start: Date
        let points: Double
        var id: Date { start }
    }

    struct Gap: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    let buckets: [Bucket]
    let gaps: [Gap]
    let resets: [Date]
    let bucketWidth: TimeInterval

    var isEmpty: Bool { buckets.allSatisfy { $0.points == 0 } }

    var bucketLabel: String {
        bucketWidth >= 3600 ? L("bucket_hour") : L("bucket_15min")
    }

    init(samples: [UsageSample], limitID: String, range: ChartRange, pollingMinutes: Int) {
        let width: TimeInterval = range == .sixHours ? 900 : 3600
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        let origin = floor(start.timeIntervalSince1970 / width) * width

        // Two missed polls in a row is a gap; one late poll is just a late poll.
        let tolerance = TimeInterval(pollingMinutes * 60) * 2.5

        let readings = samples
            .compactMap { sample -> (Date, Double)? in
                guard let value = sample.values[limitID] else { return nil }
                return (sample.date, value)
            }
            .filter { $0.0 >= start.addingTimeInterval(-tolerance) }
            .sorted { $0.0 < $1.0 }

        var totals: [Int: Double] = [:]
        var gaps: [Gap] = []
        var resets: [Date] = []

        for (previous, current) in zip(readings, readings.dropFirst()) {
            let interval = current.0.timeIntervalSince(previous.0)
            guard interval <= tolerance else {
                gaps.append(Gap(start: previous.0, end: current.0))
                continue
            }

            let burned: Double
            if current.1 >= previous.1 {
                burned = current.1 - previous.1
            } else {
                resets.append(current.0)
                burned = current.1
            }
            guard burned > 0, current.0 >= start else { continue }

            let index = Int((current.0.timeIntervalSince1970 - origin) / width)
            totals[index, default: 0] += burned
        }

        let count = max(1, Int(ceil((end.timeIntervalSince1970 - origin) / width)))
        self.buckets = (0..<count).map { index in
            Bucket(
                start: Date(timeIntervalSince1970: origin + Double(index) * width),
                points: totals[index] ?? 0
            )
        }
        self.gaps = gaps
        self.resets = resets
        self.bucketWidth = width
    }
}

/// The level of one window over time, for a sparkline.
struct LevelSeries: Identifiable {
    struct Point: Identifiable {
        let date: Date
        let percent: Double
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    let limit: UsageLimit
    let points: [Point]

    var id: String { limit.id }
    var isEmpty: Bool { points.count < 2 }

    /// A weekly window barely moves between two polls, so a fifteen-minute resolution
    /// buys nothing on a 22-point-high line — one point per hour is plenty.
    init(samples: [UsageSample], limit: UsageLimit, duration: TimeInterval) {
        self.limit = limit
        let cutoff = Date().addingTimeInterval(-duration)
        var perHour: [Int: Point] = [:]

        for sample in samples where sample.date >= cutoff {
            guard let value = sample.values[limit.id] else { continue }
            let hour = Int(sample.date.timeIntervalSince1970 / 3600)
            perHour[hour] = Point(date: sample.date, percent: value)
        }

        self.points = perHour.values.sorted { $0.date < $1.date }
    }
}
