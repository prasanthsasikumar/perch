import XCTest
@testable import AnalyticsPlugin

final class RunReportResponseTests: XCTestCase {
    private func decode(_ json: String) throws -> RunReportResponse {
        try JSONDecoder().decode(RunReportResponse.self, from: Data(json.utf8))
    }

    // MARK: - Totals

    func testTotalsReadMetricsByHeaderName() throws {
        let response = try decode("""
        {
          "metricHeaders": [
            {"name": "activeUsers", "type": "TYPE_INTEGER"},
            {"name": "sessions", "type": "TYPE_INTEGER"},
            {"name": "screenPageViews", "type": "TYPE_INTEGER"},
            {"name": "bounceRate", "type": "TYPE_FLOAT"},
            {"name": "averageSessionDuration", "type": "TYPE_SECONDS"}
          ],
          "rows": [{"metricValues": [
            {"value": "1204"}, {"value": "1832"}, {"value": "3401"},
            {"value": "0.4231"}, {"value": "95.42"}
          ]}]
        }
        """)

        let totals = response.totals()
        XCTAssertEqual(totals.activeUsers, 1204)
        XCTAssertEqual(totals.sessions, 1832)
        XCTAssertEqual(totals.screenPageViews, 3401)
        XCTAssertEqual(totals.bounceRate, 0.4231, accuracy: 0.0001)
        XCTAssertEqual(totals.averageSessionDuration, 95.42, accuracy: 0.01)
    }

    /// The whole point of looking metrics up by name: a response that lists
    /// them in a different order than the request must still read correctly.
    func testMetricOrderInTheResponseDoesNotMatter() throws {
        let response = try decode("""
        {
          "metricHeaders": [{"name": "sessions"}, {"name": "activeUsers"}],
          "rows": [{"metricValues": [{"value": "99"}, {"value": "7"}]}]
        }
        """)
        XCTAssertEqual(response.totals().activeUsers, 7)
        XCTAssertEqual(response.totals().sessions, 99)
    }

    /// A property with no traffic in the window returns no rows at all. That
    /// is a zero, not a failure.
    func testEmptyResponseYieldsZeros() throws {
        let response = try decode("""
        {"metricHeaders": [{"name": "activeUsers"}], "rowCount": 0}
        """)
        XCTAssertEqual(response.totals().activeUsers, 0)
        XCTAssertEqual(response.dailyPoints(), [])
    }

    func testMetricsMissingFromTheResponseReadAsZero() throws {
        let response = try decode("""
        {
          "metricHeaders": [{"name": "activeUsers"}],
          "rows": [{"metricValues": [{"value": "5"}]}]
        }
        """)
        XCTAssertEqual(response.totals().activeUsers, 5)
        XCTAssertEqual(response.totals().screenPageViews, 0)
    }

    // MARK: - Two date ranges

    /// GA tags each row with the range it came from and does not promise an
    /// order, so the tag — not the position — has to pick the week apart.
    func testDateRangeTagSelectsTheRightWeek() throws {
        let response = try decode("""
        {
          "dimensionHeaders": [{"name": "dateRange"}],
          "metricHeaders": [{"name": "activeUsers"}, {"name": "sessions"}],
          "rows": [
            {"dimensionValues": [{"value": "date_range_1"}],
             "metricValues": [{"value": "273"}, {"value": "505"}]},
            {"dimensionValues": [{"value": "date_range_0"}],
             "metricValues": [{"value": "312"}, {"value": "489"}]}
          ]
        }
        """)

        XCTAssertEqual(response.totals(forDateRange: 0).activeUsers, 312)
        XCTAssertEqual(response.totals(forDateRange: 0).sessions, 489)
        XCTAssertEqual(response.totals(forDateRange: 1).activeUsers, 273)
        XCTAssertEqual(response.totals(forDateRange: 1).sessions, 505)
    }

    func testMissingDateRangeYieldsZeros() throws {
        let response = try decode("""
        {
          "dimensionHeaders": [{"name": "dateRange"}],
          "metricHeaders": [{"name": "activeUsers"}],
          "rows": [{"dimensionValues": [{"value": "date_range_0"}],
                    "metricValues": [{"value": "10"}]}]
        }
        """)
        XCTAssertEqual(response.totals(forDateRange: 1).activeUsers, 0)
    }

    // MARK: - Daily

    func testDailyPointsCarryTheDateDimension() throws {
        let response = try decode("""
        {
          "dimensionHeaders": [{"name": "date"}],
          "metricHeaders": [{"name": "activeUsers"}, {"name": "sessions"}],
          "rows": [
            {"dimensionValues": [{"value": "20260722"}],
             "metricValues": [{"value": "45"}, {"value": "60"}]},
            {"dimensionValues": [{"value": "20260723"}],
             "metricValues": [{"value": "52"}, {"value": "71"}]}
          ]
        }
        """)

        let points = response.dailyPoints()
        XCTAssertEqual(points.map(\.date), ["20260722", "20260723"])
        XCTAssertEqual(points.map(\.activeUsers), [45, 52])
        XCTAssertEqual(points.map(\.sessions), [60, 71])
    }

    /// The sparkline is meaningless if the days arrive out of order.
    func testDailyPointsAreSortedByDate() throws {
        let response = try decode("""
        {
          "dimensionHeaders": [{"name": "date"}],
          "metricHeaders": [{"name": "activeUsers"}],
          "rows": [
            {"dimensionValues": [{"value": "20260725"}], "metricValues": [{"value": "3"}]},
            {"dimensionValues": [{"value": "20260721"}], "metricValues": [{"value": "1"}]}
          ]
        }
        """)
        XCTAssertEqual(response.dailyPoints().map(\.date), ["20260721", "20260725"])
    }
}
