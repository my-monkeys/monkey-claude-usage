import Charts
import MonkeyClaudeUsageCore
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case sixHours, day, week, month

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .sixHours: "range_6h"
        case .day: "range_24h"
        case .week: "range_7d"
        case .month: "range_30d"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .sixHours: 6 * 3600
        case .day: 24 * 3600
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }
}

/// Utilisation over time, one line per limit. The endpoint returns no history, so this
/// is built from what the app has polled since it was installed.
struct UsageChartView: View {
    let samples: [UsageSample]
    let limits: [UsageLimit]
    @Binding var range: ChartRange

    /// A plot this small cannot show more than a couple hundred points, and a month of
    /// five-minute polling is several thousand.
    private static let maximumPoints = 160

    private struct Point: Identifiable {
        let date: Date
        let series: String
        let percent: Double

        /// Derived, not a fresh UUID per evaluation: `points` is a computed property, so
        /// random ids would hand Swift Charts a brand new dataset on every redraw.
        var id: String { "\(series)|\(date.timeIntervalSince1970)" }
    }

    private var points: [Point] {
        let cutoff = Date().addingTimeInterval(-range.duration)
        let names = Dictionary(uniqueKeysWithValues: limits.map { ($0.id, $0.fullLabel) })
        let window = samples.filter { $0.date >= cutoff }
        let stride = max(1, window.count / Self.maximumPoints)

        return window
            .enumerated()
            .filter { $0.offset % stride == 0 || $0.offset == window.count - 1 }
            .flatMap { _, sample in
                sample.values.compactMap { key, value in
                    names[key].map { Point(date: sample.date, series: $0, percent: value) }
                }
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("history"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(ChartRange.allCases) { value in
                        Text(L(value.titleKey)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 168)
                .controlSize(.mini)
            }

            let data = points
            if data.count < 2 {
                Text(L("history_empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                Chart(data) { point in
                    LineMark(
                        x: .value("t", point.date),
                        y: .value("%", point.percent)
                    )
                    .foregroundStyle(by: .value("s", point.series))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
                .chartYScale(domain: 0...100)
                .chartForegroundStyleScale(
                    domain: limits.map(\.fullLabel),
                    range: Array(Theme.seriesPalette.prefix(limits.count))
                )
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) {
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: Decimal.FormatStyle.Percent.percent.scale(1))
                            .font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: axisFormat).font(.system(size: 9))
                    }
                }
                .chartLegend(position: .bottom, spacing: 6)
                .frame(height: 92)
            }
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .sixHours, .day: .dateTime.hour().minute()
        case .week, .month: .dateTime.day().month(.abbreviated)
        }
    }
}
