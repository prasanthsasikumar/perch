import Foundation
@testable import MarketPlugin
import XCTest

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testJustNow() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-5), now: now), "just now")
    }

    func testMinutes() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-300), now: now), "5m ago")
    }

    func testHours() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    func testDays() {
        XCTAssertEqual(
            RelativeTime.describe(now.addingTimeInterval(-172_800), now: now), "2d ago"
        )
    }

    func testAFutureDateReadsAsJustNowRatherThanNegative() {
        // Clock skew should not produce "-3m ago".
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(60), now: now), "just now")
    }
}
