import Foundation

/// Compact "time left" rendering. Two variants: one for the menu bar, where four
/// characters is the budget, and a roomier one for the popover.
public enum Countdown {
    public static func short(until date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let dayUnit = AppLanguage.resolved == .fr ? "j" : "d"

        if seconds >= 86_400 {
            let days = Int(seconds / 86_400)
            let hours = Int((seconds - Double(days) * 86_400) / 3600)
            return hours > 0 && days < 3 ? "\(days)\(dayUnit)\(hours)" : "\(days)\(dayUnit)"
        }
        if seconds >= 3600 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds - Double(hours) * 3600) / 60)
            return String(format: "%dh%02d", hours, minutes)
        }
        if seconds >= 60 { return "\(Int(seconds / 60))m" }
        return "<1m"
    }

    public static func long(until date: Date, now: Date = Date()) -> String {
        duration(max(0, date.timeIntervalSince(now)))
    }

    public static func elapsed(since date: Date, now: Date = Date()) -> String {
        duration(max(0, now.timeIntervalSince(date)))
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let french = AppLanguage.resolved == .fr

        if seconds >= 86_400 {
            let days = Int(seconds / 86_400)
            let hours = Int((seconds - Double(days) * 86_400) / 3600)
            let dayWord = french ? (days > 1 ? "jours" : "jour") : (days > 1 ? "days" : "day")
            return hours > 0 ? "\(days) \(dayWord) \(hours) h" : "\(days) \(dayWord)"
        }
        if seconds >= 3600 {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds - Double(hours) * 3600) / 60)
            return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h"
        }
        if seconds >= 60 { return "\(Int(seconds / 60)) min" }
        return french ? "moins d'une minute" : "less than a minute"
    }
}
