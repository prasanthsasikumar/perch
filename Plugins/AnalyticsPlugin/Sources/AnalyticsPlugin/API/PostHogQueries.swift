import Foundation

/// The HogQL this plugin sends, built as plain strings so the tests can read
/// exactly what PostHog will be asked.
///
/// Every query aggregates inside PostHog and returns a handful of rows; none
/// of them pull raw events back over the wire. The project is shared by every
/// site, so each one filters on `properties.$host`, and each counts
/// `$pageview` only: autocapture clicks and the like would otherwise inflate
/// "views" and make the numbers incomparable with GA.
///
/// Day boundaries come from `toDate(timestamp)`, which HogQL evaluates in the
/// project's own timezone — the same reason the GA path trusts the
/// property's calendar rather than the Mac's.
enum PostHogQueries {
    /// Every PostHog read is capped at 100 rows unless the query says
    /// otherwise, which thirteen sites by eight days would quietly exceed.
    static let rowLimit = 10_000

    /// How many rows each breakdown table keeps, matching the GA path.
    static let breakdownRowLimit = 8

    /// The dates the queries compare against, as `yyyy-MM-dd`. Derived from
    /// the same `DateWindows` the GA path uses so the two sources measure the
    /// same weeks.
    struct Window: Equatable {
        let start30: String
        let currentStart: String
        let previousStart: String
        let previousEnd: String
        let today: String

        init(today: Date, calendar: Calendar) {
            let windows = DateWindows(today: today, calendar: calendar)
            let thirty = calendar.date(byAdding: .day, value: -30, to: today) ?? today
            start30 = Self.iso(thirty, calendar)
            currentStart = windows.currentWeek.startDate
            previousStart = windows.previousWeek.startDate
            previousEnd = windows.previousWeek.endDate
            self.today = windows.currentWeek.endDate
        }

        private static func iso(_ date: Date, _ calendar: Calendar) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    // MARK: - Discovery

    /// Every domain that has served a page in the last 30 days. These are the
    /// PostHog equivalent of GA properties.
    static func hosts() -> String {
        """
        SELECT properties.$host AS host, count() AS views
        FROM events
        WHERE event = '$pageview'
            AND timestamp >= now() - INTERVAL 30 DAY
            AND properties.$host IS NOT NULL
            AND properties.$host != ''
        GROUP BY host
        ORDER BY views DESC
        LIMIT 500
        """
    }

    // MARK: - Stats

    /// Last 30 days, this week and last week, one row per host, in one query.
    ///
    /// Visitors are `count(DISTINCT distinct_id)`. The sites capture in
    /// cookieless mode, where PostHog hashes a fresh distinct id every day,
    /// so a visitor who comes back tomorrow counts twice over a week: these
    /// are visitor-days, and run high next to GA's users over any window
    /// longer than a day.
    static func totals(hosts: [String], window: Window) -> String {
        let current = "toDate(timestamp) >= toDate(\(literal(window.currentStart)))"
        let previous = "toDate(timestamp) >= toDate(\(literal(window.previousStart))) "
            + "AND toDate(timestamp) <= toDate(\(literal(window.previousEnd)))"
        return """
        SELECT
            properties.$host AS host,
            count(DISTINCT distinct_id) AS users_30d,
            count(DISTINCT properties.$session_id) AS sessions_30d,
            count() AS views_30d,
            count(DISTINCT if(\(current), distinct_id, NULL)) AS users_current,
            count(DISTINCT if(\(current), properties.$session_id, NULL)) AS sessions_current,
            countIf(\(current)) AS views_current,
            count(DISTINCT if(\(previous), distinct_id, NULL)) AS users_previous,
            count(DISTINCT if(\(previous), properties.$session_id, NULL)) AS sessions_previous,
            countIf(\(previous)) AS views_previous
        FROM events
        WHERE \(pageviews(hosts: hosts, from: window.start30, to: window.today))
        GROUP BY host
        LIMIT \(rowLimit)
        """
    }

    /// Visitors and sessions per host per day across the trailing week.
    static func daily(hosts: [String], window: Window) -> String {
        """
        SELECT
            properties.$host AS host,
            toDate(timestamp) AS day,
            count(DISTINCT distinct_id) AS users,
            count(DISTINCT properties.$session_id) AS sessions
        FROM events
        WHERE \(pageviews(hosts: hosts, from: window.currentStart, to: window.today))
        GROUP BY host, day
        ORDER BY host, day
        LIMIT \(rowLimit)
        """
    }

    // MARK: - Breakdown

    /// The week's headline for one host, for the top of the detail window.
    static func breakdownTotals(host: String, window: Window) -> String {
        """
        SELECT
            count(DISTINCT distinct_id) AS users,
            count(DISTINCT properties.$session_id) AS sessions,
            count() AS views
        FROM events
        WHERE \(pageviews(hosts: [host], from: window.currentStart, to: window.today))
        """
    }

    /// The event property each breakdown table groups by. `nil` for the
    /// dimensions PostHog has no use for here: every row of a per-host
    /// breakdown would share one hostname.
    static func expression(for dimension: PropertyBreakdown.Dimension) -> String? {
        switch dimension {
        case .source: "properties.$referring_domain"
        case .country: "properties.$geoip_country_name"
        case .city: "properties.$geoip_city_name"
        case .device: "properties.$device_type"
        case .browser: "properties.$browser"
        case .landingPage: "properties.$pathname"
        case .hostName: nil
        }
    }

    /// One table of the detail window, or `nil` when the dimension is skipped.
    static func breakdown(
        _ dimension: PropertyBreakdown.Dimension, host: String, window: Window
    ) -> String? {
        guard let expression = expression(for: dimension) else { return nil }
        let filter = pageviews(hosts: [host], from: window.currentStart, to: window.today)

        // A landing page is the first page of a session, not any page, so it
        // is grouped per session first. Grouping plain pageviews by path would
        // answer "popular pages", which is a different question.
        if dimension == .landingPage {
            return """
            SELECT value, count(DISTINCT visitor) AS users, count() AS sessions, sum(views) AS views
            FROM (
                SELECT
                    properties.$session_id AS session,
                    argMin(\(expression), timestamp) AS value,
                    any(distinct_id) AS visitor,
                    count() AS views
                FROM events
                WHERE \(filter) AND properties.$session_id IS NOT NULL
                GROUP BY session
            )
            GROUP BY value
            ORDER BY sessions DESC
            LIMIT \(breakdownRowLimit)
            """
        }

        return """
        SELECT
            \(expression) AS value,
            count(DISTINCT distinct_id) AS users,
            count(DISTINCT properties.$session_id) AS sessions,
            count() AS views
        FROM events
        WHERE \(filter)
        GROUP BY value
        ORDER BY sessions DESC
        LIMIT \(breakdownRowLimit)
        """
    }

    // MARK: - Pieces

    private static func pageviews(hosts: [String], from start: String, to end: String) -> String {
        let list = hosts.map(literal).joined(separator: ", ")
        return """
        event = '$pageview'
                AND properties.$host IN (\(list))
                AND toDate(timestamp) >= toDate(\(literal(start)))
                AND toDate(timestamp) <= toDate(\(literal(end)))
        """
    }

    /// A HogQL string literal. Hosts come from PostHog itself or from the
    /// add-by-hand field, and the query API does not document bound
    /// parameters, so quoting has to be done here — and done right, or a
    /// stray quote in a typed host breaks the query for every site.
    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
