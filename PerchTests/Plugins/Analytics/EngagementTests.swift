import XCTest
@testable import AnalyticsPlugin

final class EngagementTests: XCTestCase {
    func testEngagementRateIsEngagedOverAllSessions() {
        let totals = PropertyStats.Totals(sessions: 181, engagedSessions: 13)
        XCTAssertEqual(totals.engagementRate, 13.0 / 181.0, accuracy: 0.0001)
    }

    func testAverageEngagementTimeIsPerUser() {
        let totals = PropertyStats.Totals(activeUsers: 20, userEngagementDuration: 552)
        XCTAssertEqual(totals.averageEngagementTime, 27.6, accuracy: 0.01)
    }

    func testNoTrafficHasNoRatesRatherThanNaN() {
        let totals = PropertyStats.Totals()
        XCTAssertEqual(totals.engagementRate, 0)
        XCTAssertEqual(totals.averageEngagementTime, 0)
        XCTAssertFalse(totals.looksLikeBots)
    }

    /// homepage this week: 181 sessions, 13 engaged.
    func testLowEngagementOnRealVolumeLooksLikeBots() {
        XCTAssertTrue(PropertyStats.Totals(sessions: 181, engagedSessions: 13).looksLikeBots)
    }

    /// astro this week: half the sessions engaged.
    func testHealthyEngagementDoesNotLookLikeBots() {
        XCTAssertFalse(PropertyStats.Totals(sessions: 24, engagedSessions: 12).looksLikeBots)
    }

    /// wasd: three sessions is too few to call anything.
    func testTooFewSessionsToJudge() {
        XCTAssertFalse(PropertyStats.Totals(sessions: 3, engagedSessions: 0).looksLikeBots)
    }

    /// A row with nobody engaging and no time on site is the signature the
    /// detail window dims.
    func testZeroEngagementRowIsFlagged() {
        XCTAssertTrue(PropertyStats.Totals(activeUsers: 116, sessions: 116).hasNoEngagement)
        XCTAssertFalse(PropertyStats.Totals(activeUsers: 7, sessions: 9, engagedSessions: 6).hasNoEngagement)
    }
}
