import Foundation

/// A GA4 date range. Both ends are inclusive and either may be one of GA's
/// relative keywords (`today`, `30daysAgo`) instead of an ISO date.
public struct GADateRange: Equatable, Sendable {
    public let startDate: String
    public let endDate: String

    public init(startDate: String, endDate: String) {
        self.startDate = startDate
        self.endDate = endDate
    }

    public static let last30Days = GADateRange(startDate: "30daysAgo", endDate: "today")
    public static let last7Days = GADateRange(startDate: "7daysAgo", endDate: "today")
}

/// The week boundaries the summary compares.
///
/// `today` is injected rather than read from the clock so the arithmetic can be
/// tested without the tests changing answer overnight.
public struct DateWindows: Equatable, Sendable {
    public let currentWeek: GADateRange
    public let previousWeek: GADateRange

    public init(today: Date, calendar: Calendar = .current) {
        let day = { (offset: Int) -> String in
            Self.iso(calendar.date(byAdding: .day, value: offset, to: today) ?? today, calendar)
        }
        // Matching the script: the current week runs back seven days from
        // today inclusive, and the previous week is the seven days before it.
        currentWeek = GADateRange(startDate: day(-7), endDate: Self.iso(today, calendar))
        previousWeek = GADateRange(startDate: day(-14), endDate: day(-8))
    }

    private static func iso(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
