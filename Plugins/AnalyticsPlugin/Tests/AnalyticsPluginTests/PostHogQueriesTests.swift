import XCTest
@testable import AnalyticsPlugin

final class PostHogQueriesTests: XCTestCase {
    private let window = PostHogQueries.Window(today: PostHogFixture.today, calendar: PostHogFixture.utc)

    /// The same weeks the GA path compares, so switching sources does not
    /// silently change what "this week" means.
    func testWindowMatchesTheGADateWindows() {
        XCTAssertEqual(window.today, "2026-11-08")
        XCTAssertEqual(window.currentStart, "2026-11-01")
        XCTAssertEqual(window.previousStart, "2026-10-25")
        XCTAssertEqual(window.previousEnd, "2026-10-31")
        XCTAssertEqual(window.start30, "2026-10-09")
    }

    func testDiscoveryCountsOnlyPageviewsFromTheLast30Days() {
        let query = PostHogQueries.hosts()
        XCTAssertTrue(query.contains("properties.$host AS host"))
        XCTAssertTrue(query.contains("event = '$pageview'"))
        XCTAssertTrue(query.contains("INTERVAL 30 DAY"))
        XCTAssertTrue(query.contains("GROUP BY host"))
    }

    func testTotalsFilterToTheWatchedHostsAndAggregate() {
        let query = PostHogQueries.totals(hosts: ["a.example", "b.example"], window: window)
        XCTAssertTrue(query.contains("properties.$host IN ('a.example', 'b.example')"))
        XCTAssertTrue(query.contains("event = '$pageview'"))
        XCTAssertTrue(query.contains("toDate(timestamp) >= toDate('2026-10-09')"))
        XCTAssertTrue(query.contains("toDate(timestamp) <= toDate('2026-11-08')"))
        XCTAssertTrue(query.contains("count(DISTINCT distinct_id) AS users_30d"))
        XCTAssertTrue(query.contains("count(DISTINCT properties.$session_id) AS sessions_30d"))
        XCTAssertTrue(query.contains("count() AS views_30d"))
        XCTAssertTrue(query.contains("GROUP BY host"))
        // PostHog caps unlimited queries at 100 rows.
        XCTAssertTrue(query.contains("LIMIT \(PostHogQueries.rowLimit)"))
    }

    func testDailyGroupsByHostAndDayOverTheTrailingWeek() {
        let query = PostHogQueries.daily(hosts: ["a.example"], window: window)
        XCTAssertTrue(query.contains("toDate(timestamp) AS day"))
        XCTAssertTrue(query.contains("GROUP BY host, day"))
        XCTAssertTrue(query.contains("toDate(timestamp) >= toDate('2026-11-01')"))
    }

    /// A quote in a typed host must not end the literal early and break the
    /// query for every site.
    func testLiteralsEscapeQuotesAndBackslashes() {
        XCTAssertEqual(PostHogQueries.literal("a.example"), "'a.example'")
        XCTAssertEqual(PostHogQueries.literal("it's"), #"'it\'s'"#)
        XCTAssertEqual(PostHogQueries.literal(#"a\b"#), #"'a\\b'"#)
    }

    func testLandingPagesAreEachSessionsFirstPage() throws {
        let query = try XCTUnwrap(PostHogQueries.breakdown(.landingPage, host: "a.example", window: window))
        XCTAssertTrue(query.contains("argMin(properties.$pathname, timestamp)"))
        XCTAssertTrue(query.contains("GROUP BY session"))
        XCTAssertTrue(query.contains("LIMIT \(PostHogQueries.breakdownRowLimit)"))
    }

    func testOtherBreakdownsGroupByTheirProperty() throws {
        let query = try XCTUnwrap(PostHogQueries.breakdown(.country, host: "a.example", window: window))
        XCTAssertTrue(query.contains("properties.$geoip_country_name AS value"))
        XCTAssertTrue(query.contains("properties.$host IN ('a.example')"))
    }

    /// Every row of a single-host breakdown would share one hostname.
    func testHostnameBreakdownIsSkipped() {
        XCTAssertNil(PostHogQueries.breakdown(.hostName, host: "a.example", window: window))
    }

    // MARK: - Request

    func testRequestShape() throws {
        let request = try LivePostHogAPI.request(
            for: "SELECT 1", name: "perch test", credential: PostHogFixture.credential
        )
        XCTAssertEqual(request.url?.absoluteString, "https://us.posthog.com/api/projects/12345/query/")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer phx_testkey1234")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let query = try XCTUnwrap(body["query"] as? [String: Any])
        XCTAssertEqual(query["kind"] as? String, "HogQLQuery")
        XCTAssertEqual(query["query"] as? String, "SELECT 1")
        XCTAssertEqual(body["name"] as? String, "perch test")
    }

    func testEURegionUsesTheEUHost() throws {
        let credential = PostHogCredential(region: .eu, projectID: "9", apiKey: "phx_abcdefgh")
        let request = try LivePostHogAPI.request(for: "SELECT 1", name: "x", credential: credential)
        XCTAssertEqual(request.url?.absoluteString, "https://eu.posthog.com/api/projects/9/query/")
    }
}
