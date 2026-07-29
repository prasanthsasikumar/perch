import XCTest
@testable import AnalyticsPlugin

final class DateWindowsTests: XCTestCase {
    /// Fixed so the assertions do not change answer overnight.
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: iso)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testCurrentWeekRunsBackSevenDaysFromToday() {
        let windows = DateWindows(today: date("2026-07-28"), calendar: calendar)
        XCTAssertEqual(windows.currentWeek.startDate, "2026-07-21")
        XCTAssertEqual(windows.currentWeek.endDate, "2026-07-28")
    }

    /// The two windows must not overlap, or the comparison double-counts a day.
    func testPreviousWeekEndsTheDayBeforeTheCurrentOneStarts() {
        let windows = DateWindows(today: date("2026-07-28"), calendar: calendar)
        XCTAssertEqual(windows.previousWeek.startDate, "2026-07-14")
        XCTAssertEqual(windows.previousWeek.endDate, "2026-07-20")
    }

    func testCrossesAMonthBoundary() {
        let windows = DateWindows(today: date("2026-03-03"), calendar: calendar)
        XCTAssertEqual(windows.currentWeek.startDate, "2026-02-24")
        XCTAssertEqual(windows.previousWeek.startDate, "2026-02-17")
        XCTAssertEqual(windows.previousWeek.endDate, "2026-02-23")
    }
}
