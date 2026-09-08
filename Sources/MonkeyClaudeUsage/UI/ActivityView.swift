import Charts
import MonkeyClaudeUsageCore
import SwiftUI

/// Token history read from the Claude Code transcripts on this Mac.
///
/// Deliberately not inside an account tab: the transcripts record no account, so this is
/// everything this machine ran, whichever account was signed in — saying so plainly beats
/// attaching the number to whichever account happens to be selected.
struct ActivityView: View {
    @ObservedObject var model: ActivityModel
    @Binding var range: ChartRange
    @Binding var measure: ActivityMeasure

    private struct Bar: Identifiable {
        let start: Date
        let model: String
        let tokens: Int
        var id: String { "\(model)|\(start.timeIntervalSince1970)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !model.isAvailable {
                note(L("activity_empty"))
            } else if model.slots.isEmpty {
                note(model.isScanning ? L("activity_scanning") : L("activity_empty"))
            } else {
                chart
                legend
            }

            Text(L("activity_subtitle"))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.load() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("activity"))
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text(L("activity_total", Self.compact(total)))
                .numeric()
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $measure) {
                    ForEach(ActivityMeasure.allCases, id: \.rawValue) { value in
                        Text(L(value.titleKey)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 116)

                Spacer()

                Picker("", selection: $range) {
                    ForEach(ChartRange.activityCases) { value in
                        Text(L(value.titleKey)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 168)
                .controlSize(.mini)
            }

            let data = bars
            if data.isEmpty {
                note(L("no_activity_in_range"))
            } else {
                let width = window.bucket
                Chart(data) { bar in
                    // Models stack legitimately here: unlike quota percentages, tokens add up.
                    BarMark(
                        xStart: .value("from", bar.start),
                        xEnd: .value("to", bar.start.addingTimeInterval(width * 0.78)),
                        y: .value("tokens", bar.tokens)
                    )
                    .foregroundStyle(by: .value("m", bar.model))
                    .cornerRadius(1)
                }
                .chartForegroundStyleScale(
                    domain: model.models,
                    range: Array(Theme.seriesPalette.prefix(max(1, model.models.count)))
                )
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { mark in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            Text(Self.compact(mark.as(Int.self) ?? 0)).font(.system(size: 9))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: axisFormat).font(.system(size: 9))
                    }
                }
                .frame(height: 104)
            }
        }
    }

    private var legend: some View {
        let totals = modelTotals
        return FlowRow(spacing: 10) {
            ForEach(Array(model.models.prefix(Theme.seriesPalette.count).enumerated()), id: \.element) { index, name in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.seriesPalette[index % Theme.seriesPalette.count])
                        .frame(width: 6, height: 6)
                    Text(Self.shortModelName(name))
                        .font(.system(size: 10))
                    Text(Self.compact(totals[name] ?? 0))
                        .numeric()
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // MARK: - Shaping

    private var window: (start: Date, end: Date, bucket: TimeInterval) {
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        let bucket: TimeInterval = switch range {
        case .sixHours: 900
        case .day: 3600
        case .week, .month: 86_400
        case .quarter: 86_400
        }
        return (start, end, bucket)
    }

    private var bars: [Bar] {
        let (start, end, bucket) = window
        return model.slots
            .buckets(width: bucket, since: start, until: end, measure: measure)
            .flatMap { slot in
                slot.byModel.map { Bar(start: slot.start, model: $0.key, tokens: $0.value) }
            }
    }

    private var modelTotals: [String: Int] {
        bars.reduce(into: [:]) { $0[$1.model, default: 0] += $1.tokens }
    }

    private var total: Int { modelTotals.values.reduce(0, +) }

    private var axisFormat: Date.FormatStyle {
        switch range {
        case .sixHours, .day: .dateTime.hour().minute()
        case .week, .month, .quarter: .dateTime.day().month(.abbreviated)
        }
    }

    /// `claude-fable-5-1` reads as `Fable 5.1` — the legend has room for a name, not an id.
    static func shortModelName(_ identifier: String) -> String {
        var parts = identifier.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first else { return identifier }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...: String(format: "%.1f G", Double(value) / 1e9)
        case 1_000_000...: String(format: "%.0f M", Double(value) / 1e6)
        case 1_000...: String(format: "%.0f k", Double(value) / 1e3)
        default: "\(value)"
        }
    }
}

/// Wraps its children onto as many lines as needed — the legend can carry six models.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
