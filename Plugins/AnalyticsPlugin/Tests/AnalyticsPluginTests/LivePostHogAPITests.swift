import XCTest
@testable import AnalyticsPlugin

final class LivePostHogAPITests: XCTestCase {
    private func api(_ transport: StubTransport) -> LivePostHogAPI {
        LivePostHogAPI(credential: PostHogFixture.credential, transport: transport, calendar: PostHogFixture.utc)
    }

    /// Two queries answer for every site, whatever the number of sites.
    func testStatsForEverySiteInTwoQueries() async throws {
        let totals = try PostHogFixture.data("posthog-totals")
        let daily = try PostHogFixture.data("posthog-daily")
        let transport = StubTransport { request in
            let query = PostHogFixture.hogQL(in: request) ?? ""
            return (query.contains("AS day") ? daily : totals, 200)
        }

        let results = await api(transport).stats(
            for: ["a.example", "b.example", "quiet.example"], today: PostHogFixture.today
        )

        XCTAssertEqual(transport.requests.count, 2)
        let byHost = Dictionary(uniqueKeysWithValues: results.map { ($0.0, $0.1) })
        let a = try XCTUnwrap(byHost["a.example"]).get()
        XCTAssertEqual(a.currentWeek.activeUsers, 12)
        // The trailing week, filled: PostHog omits days without pageviews,
        // and for live data a missing day is a zero.
        XCTAssertEqual(a.daily.count, 8)
        XCTAssertEqual(a.daily.first?.date, "20261101")
        XCTAssertEqual(a.daily.last?.date, "20261108")
        XCTAssertEqual(a.daily.first { $0.date == "20261107" }?.activeUsers, 0)
        XCTAssertEqual(a.latestActiveUsers, 7)
        XCTAssertFalse(a.includesEngagement)

        // No pageviews at all is zero traffic, not an error.
        let quiet = try XCTUnwrap(byHost["quiet.example"]).get()
        XCTAssertEqual(quiet.currentWeek.activeUsers, 0)
        XCTAssertEqual(quiet.latestActiveUsers, 0)
    }

    func testRejectedKeyFailsEverySiteAsACredentialProblem() async {
        let transport = StubTransport { _ in (Data(#"{"detail": "Invalid personal API key."}"#.utf8), 401) }

        let results = await api(transport).stats(for: ["a.example", "b.example"], today: PostHogFixture.today)

        XCTAssertEqual(results.count, 2)
        for (_, result) in results {
            guard case .failure(let error) = result else { return XCTFail("expected a failure") }
            XCTAssertEqual(error, .authenticationFailed("Invalid personal API key."))
            XCTAssertTrue(error.isCredentialProblem)
        }
    }

    func testMissingScopeIsPermissionDenied() async {
        let transport = StubTransport { _ in (Data(#"{"detail": "scope"}"#.utf8), 403) }
        do {
            _ = try await api(transport).discoverProperties()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? AnalyticsError, .permissionDenied)
        }
    }

    func testDiscoveryReturnsHostsAsSites() async throws {
        let hosts = try PostHogFixture.data("posthog-hosts")
        let transport = StubTransport { _ in (hosts, 200) }
        let sites = try await api(transport).discoverProperties()
        XCTAssertEqual(sites.count, 3)
        XCTAssertTrue(sites.contains(AnalyticsProperty(id: "www.flowsxr.com", displayName: "www.flowsxr.com")))
    }

    func testBreakdownSkipsHostnameAndMarksEngagementUnmeasured() async throws {
        let row = Data(#"{"columns":["value","users","sessions","views"],"results":[["Singapore",3,4,9]]}"#.utf8)
        let totals = Data(#"{"columns":["users","sessions","views"],"results":[[5,6,12]]}"#.utf8)
        let transport = StubTransport { request in
            let query = PostHogFixture.hogQL(in: request) ?? ""
            return (query.contains("AS value") || query.contains("SELECT value") ? row : totals, 200)
        }

        let breakdown = try await api(transport).breakdown(for: "a.example", today: PostHogFixture.today)

        XCTAssertEqual(breakdown.totals.activeUsers, 5)
        XCTAssertEqual(breakdown.totals.pagesPerSession, 2)
        XCTAssertFalse(breakdown.includesEngagement)
        XCTAssertEqual(
            breakdown.sections.map(\.dimension),
            [.source, .country, .city, .device, .browser, .landingPage]
        )
        XCTAssertEqual(breakdown.sections[1].rows.first?.value, "Singapore")
    }
}
