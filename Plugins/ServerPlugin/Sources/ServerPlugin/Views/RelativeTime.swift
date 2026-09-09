import Foundation

/// "just now", "4 minutes ago" — short enough for a one-line footer.
///
/// Each plugin carries its own copy rather than sharing one: they are
/// independent packages, and this is six lines.
enum RelativeTime {
    static func describe(_ date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 45 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
