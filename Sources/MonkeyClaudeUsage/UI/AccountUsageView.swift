import MonkeyClaudeUsageCore
import SwiftUI

struct AccountUsageView: View {
    @ObservedObject var monitor: AccountMonitor
    let now: Date
    @Binding var sessionRange: ChartRange
    let pollingMinutes: Int
    let onReauthorize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch monitor.state {
            case .expired:
                banner(L("signed_out"), systemImage: "person.crop.circle.badge.exclamationmark") {
                    Button(L("sign_in"), action: onReauthorize)
                        .controlSize(.small)
                }
            case let .failing(message):
                banner(message, systemImage: "exclamationmark.triangle")
            case .ready:
                EmptyView()
            }

            if let snapshot = monitor.snapshot {
                ForEach(snapshot.limits) { limit in
                    UsageBarView(limit: limit, now: now)
                }

                if let extra = snapshot.extraUsage, extra.isEnabled {
                    Divider().opacity(0.5)
                    extraUsageRow(extra)
                }

                Divider().opacity(0.5)

                QuotaHistoryView(
                    limits: snapshot.limits,
                    samples: monitor.history,
                    pollingMinutes: pollingMinutes,
                    sessionRange: $sessionRange
                )
            } else if monitor.state == .ready {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let email = monitor.account.email, email != monitor.account.label {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let plan = monitor.account.plan {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .glassChip(cornerRadius: 8)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(monitor.lastUpdated.map { L("updated_ago", Countdown.elapsed(since: $0, now: now)) }
                 ?? L("never_updated"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func extraUsageRow(_ extra: ExtraUsage) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("extra_usage"))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if let used = extra.usedAmount {
                Text(extra.limitAmount.map { "\(extra.formatted(used)) / \(extra.formatted($0))" }
                     ?? extra.formatted(used))
                    .numeric()
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func banner(
        _ message: String,
        systemImage: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
}
