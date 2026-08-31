import Foundation

/// Short relative times for a panel that is only ~320pt wide: "5m ago"
/// rather than "5 minutes ago", which wraps.
enum RelativeTime {
    static func describe(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
