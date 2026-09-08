import Charts
import MonkeyClaudeUsageCore
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case sixHours, day, week, month, quarter

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .sixHours: "range_6h"
        case .day: "range_24h"
        case .week: "range_7d"
        case .month: "range_30d"
        case .quarter: "range_90d"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .sixHours: 6 * 3600
        case .day: 24 * 3600
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 90 * 86_400
        }
    }

    /// The session window turns over five times a day, so anything past a day is noise;
    /// the local activity chart, on the other hand, has months of transcripts behind it.
    static let sessionCases: [ChartRange] = [.sixHours, .day]
    static let activityCases: [ChartRange] = [.day, .week, .month, .quarter]
}

/// Session and weekly windows do not belong on one pair of axes: one turns over five
/// times a day, the other once a week, and a shared scale flattens whichever moves less.
/// So the session gets bars of what it burned, and the weekly windows get a level line.
struct QuotaHistoryView: View {
    let limits: [UsageLimit]
    let samples: [UsageSample]
    let pollingMinutes: Int
    @Binding var sessionRange: ChartRange

    private var sessionLimits: [UsageLimit] { limits.filter(\.isSession) }
    private var weeklyLimits: [UsageLimit] { limits.filter { !$0.isSession } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = sessionLimits.first {
                sessionSection(session)
            }
            if !weeklyLimits.isEmpty {
                if !sessionLimits.isEmpty { Divider().opacity(0.4) }
                weeklySection
            }
        }
    }

    // MARK: - Session

    @ViewBuilder
    private func sessionSection(_ limit: UsageLimit) -> some View {
        let series = ConsumptionSeries(
            samples: samples,
            limitID: limit.id,
            range: sessionRange,
            pollingMinutes: pollingMinutes
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(L("burned_per_bucket", series.bucketLabel))
                Spacer()
                Picker("", selection: $sessionRange) {
                    ForEach(ChartRange.sessionCases) { value in
                        Text(L(value.titleKey)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 92)
                .controlSize(.mini)
            }

            if series.isEmpty {
                emptyNote
            } else {
                Chart {
                    // Stretches the app did not see: no reading, so no bar — saying
                    // nothing beats spreading a jump over hours it did not happen in.
                    ForEach(series.gaps) { gap in
                        RectangleMark(
                            xStart: .value("from", gap.start),
                            xEnd: .value("to", gap.end)
                        )
                        .foregroundStyle(Color.primary.opacity(0.05))
                    }

                    ForEach(series.buckets) { bucket in
                        // RectangleMark, not BarMark: a bucket is fifteen minutes wide,
                        // which is not a calendar unit, and no `BarMark` initializer takes
                        // a plottable range on *both* axes — `xStart:xEnd:y:` is the
                        // horizontal-bar form and draws a floating slab, not a column.
                        RectangleMark(
                            xStart: .value("from", bucket.start),
                            xEnd: .value("to", bucket.start.addingTimeInterval(series.bucketWidth * 0.78)),
                            yStart: .value("zero", 0),
                            yEnd: .value("pts", bucket.points)
                        )
                        .foregroundStyle(Theme.tint(for: limit.percent))
                        .cornerRadius(1.5)
                    }

                    // Where the window rolled over: the bar just left of it is a floor,
                    // since part of that period was billed before the reset.
                    ForEach(series.resets, id: \.self) { reset in
                        RuleMark(x: .value("reset", reset))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.25))
                    }
                }
                .chartXScale(domain: series.start...series.end)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { mark in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            Text("\(Int(mark.as(Double.self) ?? 0))").font(.system(size: 9))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
                    }
                }
                .frame(height: 60)
            }
        }
    }

    // MARK: - Weekly

    private var weeklySection: some View {
        let series = weeklyLimits.map {
            LevelSeries(samples: samples, limit: $0, duration: ChartRange.week.duration)
        }

        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("weekly_trend"))

            if series.allSatisfy(\.isEmpty) {
                emptyNote
            } else {
                ForEach(Array(series.enumerated()), id: \.element.id) { index, line in
                    HStack(spacing: 10) {
                        Text(line.limit.modelName ?? L("all_models"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)
                            .lineLimit(1)

                        Sparkline(
                            points: line.points,
                            tint: Theme.seriesPalette[(index + 1) % Theme.seriesPalette.count]
                        )
                        .frame(height: 22)

                        Text("\(Int(line.limit.percent.rounded())) %")
                            .numeric()
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Shared

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private var emptyNote: some View {
        Text(L("history_empty"))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

/// A level line small enough to sit on one row, pinned to 0…100 so two windows can be
/// compared by eye.
private struct Sparkline: View {
    let points: [LevelSeries.Point]
    let tint: Color

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("t", point.date), y: .value("%", point.percent))
                .foregroundStyle(tint.opacity(0.18))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", point.date), y: .value("%", point.percent))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
    }
}
