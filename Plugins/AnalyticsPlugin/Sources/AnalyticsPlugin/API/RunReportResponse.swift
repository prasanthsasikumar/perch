import Foundation

/// The shape GA4's `runReport` answers in.
///
/// Metrics come back as an array positioned by `metricHeaders`, not as a
/// dictionary, so every read has to go through the header order. Doing that
/// lookup by name here means the call sites never depend on the order their
/// request happened to list metrics in.
struct RunReportResponse: Decodable {
    struct Header: Decodable {
        let name: String
    }

    struct Value: Decodable {
        let value: String?
    }

    struct Row: Decodable {
        let dimensionValues: [Value]?
        let metricValues: [Value]?
    }

    let dimensionHeaders: [Header]?
    let metricHeaders: [Header]?
    let rows: [Row]?

    // MARK: - Lookups

    func metricIndex(_ name: String) -> Int? {
        metricHeaders?.firstIndex { $0.name == name }
    }

    func dimensionIndex(_ name: String) -> Int? {
        dimensionHeaders?.firstIndex { $0.name == name }
    }

    /// Missing metrics read as zero. A property with no traffic in a window
    /// legitimately returns no row, and that is a zero, not a failure.
    func metric(_ name: String, in row: Row?) -> Double {
        guard let row, let index = metricIndex(name),
              let raw = row.metricValues?[safe: index]?.value else { return 0 }
        return Double(raw) ?? 0
    }

    func dimension(_ name: String, in row: Row) -> String? {
        guard let index = dimensionIndex(name) else { return nil }
        return row.dimensionValues?[safe: index]?.value
    }

    // MARK: - Projections

    /// Totals from a request with a single date range and no dimensions.
    func totals() -> PropertyStats.Totals {
        totals(in: rows?.first)
    }

    /// Totals for the *n*th date range of a multi-range request.
    ///
    /// GA synthesises a `dateRange` dimension whose values are `date_range_0`,
    /// `date_range_1` and so on; row order is not promised, so the tag is what
    /// tells the two weeks apart.
    func totals(forDateRange index: Int) -> PropertyStats.Totals {
        let tag = "date_range_\(index)"
        let row = rows?.first { dimension("dateRange", in: $0) == tag }
        return totals(in: row)
    }

    func dailyPoints() -> [PropertyStats.DailyPoint] {
        (rows ?? []).compactMap { row in
            guard let date = dimension("date", in: row) else { return nil }
            return PropertyStats.DailyPoint(
                date: date,
                activeUsers: metric("activeUsers", in: row),
                sessions: metric("sessions", in: row)
            )
        }
        // GA honours the requested ordering, but the sparkline is meaningless
        // if a future response ever comes back unordered.
        .sorted { $0.date < $1.date }
    }

    private func totals(in row: Row?) -> PropertyStats.Totals {
        PropertyStats.Totals(
            activeUsers: metric("activeUsers", in: row),
            sessions: metric("sessions", in: row),
            screenPageViews: metric("screenPageViews", in: row),
            bounceRate: metric("bounceRate", in: row),
            averageSessionDuration: metric("averageSessionDuration", in: row)
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
