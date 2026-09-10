import MonkeyClaudeUsageCore
import SwiftUI

struct UsageBarView: View {
    let limit: UsageLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(limit.fullLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if limit.isActive {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.barTint(for: limit.percent))
                        .help(limit.fullLabel)
                }

                Spacer(minLength: 4)

                Text("\(Int(limit.percent.rounded())) %")
                    .numeric()
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.numberTint(for: limit.percent))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(Theme.trackOpacity))
                    Capsule()
                        .fill(Theme.barTint(for: limit.percent))
                        .frame(width: max(2, proxy.size.width * limit.fraction))
                }
            }
            .frame(height: 6)

            if let resetsAt = limit.resetsAt {
                Text(limit.isSaturated
                     ? "\(L("reached")) · \(L("resets_in", Countdown.long(until: resetsAt, now: now)))"
                     : L("resets_in", Countdown.long(until: resetsAt, now: now)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
