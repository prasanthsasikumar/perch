import Foundation

/// The shape PostHog's query endpoint answers a `HogQLQuery` in:
/// `{"columns": [...], "results": [[...], ...], "types": [...], ...}`.
///
/// Rows are positional arrays, like GA's metric values, so every read goes
/// through the column name rather than trusting the order the SELECT happened
/// to list things in.
struct HogQLResponse: Decodable {
    /// One cell. ClickHouse sends counts as numbers, dates and hosts as
    /// strings, and an absent property as `null`; anything else is kept as
    /// `.other` so one odd column cannot fail the whole decode.
    enum Value: Decodable, Equatable {
        case number(Double)
        case string(String)
        case null
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .other
            }
        }

        var double: Double {
            switch self {
            case .number(let value): value
            // Large UInt64 counts can arrive quoted.
            case .string(let text): Double(text) ?? 0
            case .null, .other: 0
            }
        }

        var string: String? {
            switch self {
            case .string(let text): text
            case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
            case .null, .other: nil
            }
        }
    }

    let columns: [String]?
    let results: [[Value]]

    // MARK: - Lookups

    func index(of column: String) -> Int? {
        columns?.firstIndex(of: column)
    }

    /// A missing column or cell reads as zero, the same rule the GA path
    /// uses: no row is no traffic, not a failure.
    func number(_ column: String, in row: [Value]) -> Double {
        guard let index = index(of: column), row.indices.contains(index) else { return 0 }
        return row[index].double
    }

    func string(_ column: String, in row: [Value]) -> String? {
        guard let index = index(of: column), row.indices.contains(index) else { return nil }
        return row[index].string
    }

    // MARK: - Projections

    /// The rows of `PostHogQueries.hosts()`, as sites.
    func sites() -> [AnalyticsProperty] {
        results.compactMap { row in
            guard let host = string("host", in: row), !host.isEmpty else { return nil }
            return AnalyticsProperty(id: host, displayName: host)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// The rows of `PostHogQueries.totals`, keyed by host. Daily points are
    /// left empty for `dailyPoints(...)` to fill.
    func totalsByHost() -> [String: PropertyStats] {
        var byHost: [String: PropertyStats] = [:]
        for row in results {
            guard let host = string("host", in: row) else { continue }
            func totals(_ suffix: String) -> PropertyStats.Totals {
                PropertyStats.Totals(
                    activeUsers: number("users_\(suffix)", in: row),
                    sessions: number("sessions_\(suffix)", in: row),
                    screenPageViews: number("views_\(suffix)", in: row)
                )
            }
            byHost[host] = PropertyStats(
                last30Days: totals("30d"),
                currentWeek: totals("current"),
                previousWeek: totals("previous"),
                daily: [],
                includesEngagement: false
            )
        }
        return byHost
    }

    /// The rows of `PostHogQueries.daily`, keyed by host, in GA's `yyyyMMdd`
    /// so the card's day labels and sparkline need no second code path.
    func dailyByHost() -> [String: [PropertyStats.DailyPoint]] {
        var byHost: [String: [PropertyStats.DailyPoint]] = [:]
        for row in results {
            guard let host = string("host", in: row), let day = string("day", in: row) else { continue }
            byHost[host, default: []].append(
                PropertyStats.DailyPoint(
                    date: Self.gaDate(day),
                    activeUsers: number("users", in: row),
                    sessions: number("sessions", in: row)
                )
            )
        }
        return byHost
    }

    /// The single row of `PostHogQueries.breakdownTotals`.
    func breakdownTotals() -> PropertyStats.Totals {
        guard let row = results.first else { return PropertyStats.Totals() }
        return totals(in: row)
    }

    func breakdownRows() -> [PropertyBreakdown.Row] {
        results.map { row in
            let value = string("value", in: row) ?? ""
            return PropertyBreakdown.Row(value: value.isEmpty ? "(not set)" : value, totals: totals(in: row))
        }
    }

    private func totals(in row: [Value]) -> PropertyStats.Totals {
        PropertyStats.Totals(
            activeUsers: number("users", in: row),
            sessions: number("sessions", in: row),
            screenPageViews: number("views", in: row)
        )
    }

    /// `2026-11-08` → `20261108`. Anything else passes through untouched.
    static func gaDate(_ isoDay: String) -> String {
        String(isoDay.prefix(10)).replacingOccurrences(of: "-", with: "")
    }
}
