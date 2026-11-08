import XCTest
@testable import AnalyticsPlugin

final class HogQLResponseTests: XCTestCase {
    private func decode(_ fixture: String) throws -> HogQLResponse {
        try JSONDecoder().decode(HogQLResponse.self, from: try PostHogFixture.data(fixture))
    }

    func testTotalsMapIntoTheGAShape() throws {
        let stats = try decode("posthog-totals").totalsByHost()
        let a = try XCTUnwrap(stats["a.example"])

        XCTAssertEqual(a.last30Days.activeUsers, 42)
        XCTAssertEqual(a.last30Days.sessions, 51)
        XCTAssertEqual(a.last30Days.screenPageViews, 130)
        XCTAssertEqual(a.currentWeek.activeUsers, 12)
        XCTAssertEqual(a.currentWeek.sessions, 14)
        XCTAssertEqual(a.currentWeek.screenPageViews, 37)
        XCTAssertEqual(a.previousWeek.activeUsers, 30)
        XCTAssertEqual(a.previousWeek.screenPageViews, 93)
        XCTAssertEqual(stats["b.example"]?.previousWeek.sessions, 0)
    }

    /// Unmeasured, so the views show it as unavailable and the bot heuristic
    /// never fires on a zero that was never counted.
    func testTotalsMarkEngagementUnmeasured() throws {
        let a = try XCTUnwrap(try decode("posthog-totals").totalsByHost()["a.example"])
        XCTAssertFalse(a.includesEngagement)
        XCTAssertEqual(a.last30Days.engagedSessions, 0)
        XCTAssertEqual(a.last30Days.bounceRate, 0)
    }

    func testDailyRowsBecomeGADates() throws {
        let daily = try decode("posthog-daily").dailyByHost()
        XCTAssertEqual(daily["a.example"]?.map(\.date), ["20261106", "20261108"])
        XCTAssertEqual(daily["a.example"]?.last?.activeUsers, 7)
        XCTAssertEqual(daily["a.example"]?.last?.sessions, 8)
        XCTAssertEqual(daily["b.example"]?.count, 1)
    }

    func testHostsBecomeSitesSortedByNameWithoutNulls() throws {
        let sites = try decode("posthog-hosts").sites()
        XCTAssertEqual(sites.map(\.id), ["alpha.example", "Beta.example", "www.flowsxr.com"])
        XCTAssertEqual(sites.first?.displayName, "alpha.example")
    }

    /// Lookups go by column name, not position.
    func testColumnsAreReadByName() throws {
        let json = #"{"columns": ["views", "host"], "results": [[5, "x.example"]]}"#
        let response = try JSONDecoder().decode(HogQLResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.sites().map(\.id), ["x.example"])
        XCTAssertEqual(response.number("views", in: response.results[0]), 5)
        XCTAssertEqual(response.number("missing", in: response.results[0]), 0)
    }

    /// Old caches have no `includesEngagement` and are all GA.
    func testStatsCachedBeforePostHogStillDecodeAsMeasured() throws {
        let json = #"{"last30Days":{},"currentWeek":{},"previousWeek":{},"daily":[]}"#
        let stats = try JSONDecoder().decode(PropertyStats.self, from: Data(json.utf8))
        XCTAssertTrue(stats.includesEngagement)
    }
}
