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
    /// The domain the chart should pin itself to — marks alone would let the first bucket
    /// start before the range and the last one run past now.
    let start: Date
    let end: Date

    var isEmpty: Bool { buckets.allSatisfy { $0.points == 0 } }

    var bucketLabel: String {
        bucketWidth >= 3600 ? L("bucket_hour") : L("bucket_15min")
    }

    init(
        samples: [UsageSample],
        limitID: String,
        range: ChartRange,
        pollingMinutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let end = now
        let start = end.addingTimeInterval(-range.duration)

        let readings = samples
            .compactMap { sample -> (Date, Double)? in
                guard let value = sample.values[limitID] else { return nil }
                return (sample.date, value)
            }
            .sorted { $0.0 < $1.0 }

        // Measured from the readings rather than taken from the current setting: someone
        // who polled every hour last week and every five minutes today would otherwise
        // see all of last week condemned as one long gap.
        let cadence = Self.cadence(of: readings, fallback: TimeInterval(pollingMinutes * 60))

        // A bucket finer than the cadence would put every reading in its own bucket and
        // leave the ones between empty, which reads as an idle period rather than as a
        // resolution the data cannot support.
        let width = max(range == .sixHours ? 900 : 3600, cadence)

        let offset = TimeInterval(calendar.timeZone.secondsFromGMT(for: start))
        let origin = floor((start.timeIntervalSince1970 + offset) / width) * width - offset

        // Two missed polls in a row is a gap; one late poll is just a late poll.
        let tolerance = cadence * 2.5

        var totals: [Int: Double] = [:]
        var gaps: [Gap] = []
        var resets: [Date] = []

        let window = readings.filter { $0.0 >= start.addingTimeInterval(-tolerance) }

        for (previous, current) in zip(window, window.dropFirst()) {
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
        self.start = Date(timeIntervalSince1970: origin)
        self.end = end
    }

    /// Median interval between readings — robust to the one long gap a sleeping Mac
    /// leaves behind, which a mean is not.
    private static func cadence(of readings: [(Date, Double)], fallback: TimeInterval) -> TimeInterval {
        let intervals = zip(readings, readings.dropFirst())
            .map { $1.0.timeIntervalSince($0.0) }
            .filter { $0 > 0 }
            .sorted()
        guard !intervals.isEmpty else { return fallback }
        return intervals[intervals.count / 2]
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
