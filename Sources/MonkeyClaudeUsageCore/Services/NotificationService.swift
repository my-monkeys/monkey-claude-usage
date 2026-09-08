import Foundation
import UserNotifications

/// Fires once per threshold crossing, per account and per limit. State is kept in
/// memory only: a relaunch re-notifies at most once for a limit already past a step.
@MainActor
public final class NotificationService {
    private static let thresholds: [Double] = [80, 95, 100]

    private var lastNotified: [String: Double] = [:]
    private var isAuthorized = false

    public init() {}

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.isAuthorized = granted }
        }
    }

    public func check(account: Account, snapshot: UsageSnapshot?) {
        guard isAuthorized,
              UserDefaults.standard.object(forKey: PreferenceKey.notificationsEnabled) as? Bool ?? true,
              let snapshot else { return }

        for limit in snapshot.limits {
            let key = "\(account.id.uuidString)|\(limit.id)"
            // A window can be locked well below 100 %; that still means "you are blocked".
            let crossed = limit.isSaturated ? 100 : Self.thresholds.last { limit.percent >= $0 }

            guard let crossed else {
                lastNotified[key] = nil
                continue
            }
            guard lastNotified[key] != crossed else { continue }
            lastNotified[key] = crossed
            notify(account: account, limit: limit, threshold: crossed)
        }
    }

    private func notify(account: Account, limit: UsageLimit, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(account.displayName) — \(limit.fullLabel)"
        if threshold >= 100, let resetsAt = limit.resetsAt {
            content.body = "\(L("reached")) · \(L("resets_in", Countdown.long(until: resetsAt)))"
        } else {
            content.body = "\(Int(limit.percent)) %"
        }
        content.sound = threshold >= 100 ? .default : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
