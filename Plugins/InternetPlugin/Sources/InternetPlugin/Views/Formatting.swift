import Foundation

enum Format {
    static func milliseconds(_ value: Double) -> String {
        "\(Int(value.rounded())) ms"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Whole megabits above ten, where a decimal is noise; one place below,
    /// where 2.4 and 2.9 are a real difference.
    static func speed(_ megabitsPerSecond: Double) -> String {
        megabitsPerSecond >= 10
            ? "\(Int(megabitsPerSecond.rounded())) Mbps"
            : String(format: "%.1f Mbps", megabitsPerSecond)
    }
}

/// "just now", "4 minutes ago". Each plugin carries its own copy, as the
/// others do: they are independent packages.
enum RelativeTime {
    static func describe(_ date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 45 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
