import Foundation

/// Short relative times for a panel that is only ~320pt wide.
///
/// `RelativeDateTimeFormatter` produces "5 minutes ago", which wraps. This
/// produces "5m ago", which does not.
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
