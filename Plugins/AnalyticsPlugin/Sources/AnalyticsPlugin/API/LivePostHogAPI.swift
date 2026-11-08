import Foundation

/// PostHog over its HogQL query endpoint:
/// `POST {host}/api/projects/{id}/query/` with a personal API key.
///
/// One PostHog project holds every site, so a "property" here is a domain
/// (`$host`), and the per-site stats the GA path fetches one property at a
/// time are fetched for all sites at once.
public struct LivePostHogAPI: GoogleAnalyticsAPI {
    /// PostHog caps a project at three concurrent queries. The detail window
    /// stays under that so its tables do not fail each other with 429s.
    static let maxConcurrentQueries = 3

    private let credential: PostHogCredential
    private let transport: HTTPTransport
    private let calendar: Calendar

    /// There is no account address to grant access to; the key either has
    /// the project or it does not.
    public let clientEmail = ""

    public init(
        credential: PostHogCredential,
        transport: HTTPTransport = URLSessionTransport(),
        calendar: Calendar = .current
    ) {
        self.credential = credential
        self.transport = transport
        self.calendar = calendar
    }

    // MARK: - Reports

    public func stats(for propertyID: String, today: Date) async throws -> PropertyStats {
        let results = await stats(for: [propertyID], today: today)
        guard let result = results.first?.1 else { return PropertyStats(includesEngagement: false) }
        return try result.get()
    }

    public func stats(
        for propertyIDs: [String], today: Date
    ) async -> [(String, Result<PropertyStats, AnalyticsError>)] {
        guard !propertyIDs.isEmpty else { return [] }
        let window = PostHogQueries.Window(today: today, calendar: calendar)
        do {
            async let totals = run(PostHogQueries.totals(hosts: propertyIDs, window: window), name: "perch totals")
            async let daily = run(PostHogQueries.daily(hosts: propertyIDs, window: window), name: "perch daily")
            let (totalsResponse, dailyResponse) = try await (totals, daily)

            let totalsByHost = totalsResponse.totalsByHost()
            let dailyByHost = dailyResponse.dailyByHost()
            let days = Self.days(from: window.currentStart, to: window.today)

            return propertyIDs.map { host in
                // A host with no pageviews in the window gets no row at all,
                // which is zero traffic rather than a failure.
                var stats = totalsByHost[host] ?? PropertyStats(includesEngagement: false)
                stats.daily = Self.filled(dailyByHost[host] ?? [], days: days)
                return (host, .success(stats))
            }
        } catch {
            // One query answers for every site, so one failure is everyone's.
            let failure = (error as? AnalyticsError) ?? .malformedResponse
            return propertyIDs.map { ($0, .failure(failure)) }
        }
    }

    public func breakdown(for propertyID: String, today: Date) async throws -> PropertyBreakdown {
        let window = PostHogQueries.Window(today: today, calendar: calendar)
        let queries: [(PropertyBreakdown.Dimension, String)] = PropertyBreakdown.Dimension.allCases.compactMap { dimension in
            PostHogQueries.breakdown(dimension, host: propertyID, window: window).map { (dimension, $0) }
        }

        let totals = try await run(
            PostHogQueries.breakdownTotals(host: propertyID, window: window), name: "perch breakdown totals"
        ).breakdownTotals()

        // In batches of the concurrency cap: serially the window takes
        // seconds to fill, and all at once PostHog refuses some of them.
        var sections: [PropertyBreakdown.Section] = []
        var start = 0
        while start < queries.count {
            let batch = queries[start..<min(start + Self.maxConcurrentQueries, queries.count)]
            let answered = try await withThrowingTaskGroup(
                of: PropertyBreakdown.Section.self
            ) { group -> [PropertyBreakdown.Section] in
                for (dimension, query) in batch {
                    group.addTask {
                        let response = try await run(query, name: "perch breakdown \(dimension.rawValue)")
                        return PropertyBreakdown.Section(dimension: dimension, rows: response.breakdownRows())
                    }
                }
                var collected: [PropertyBreakdown.Section] = []
                for try await section in group { collected.append(section) }
                return collected
            }
            sections += answered
            start += Self.maxConcurrentQueries
        }

        let order = PropertyBreakdown.Dimension.allCases
        sections.sort { order.firstIndex(of: $0.dimension)! < order.firstIndex(of: $1.dimension)! }
        return PropertyBreakdown(totals: totals, sections: sections, includesEngagement: false)
    }

    public func discoverProperties() async throws -> [AnalyticsProperty] {
        try await run(PostHogQueries.hosts(), name: "perch sites").sites()
    }

    // MARK: - Requests

    /// The request for one HogQL query. Split out so the tests can check the
    /// URL, headers and body without a transport.
    static func request(for query: String, name: String, credential: PostHogCredential) throws -> URLRequest {
        let url = credential.region.host
            .appendingPathComponent("api/projects/\(credential.projectID)/query/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.apiKey)", forHTTPHeaderField: "Authorization")
        // `name` is optional, but it is what shows in PostHog's own query log,
        // which is where anyone would look to see what Perch is costing them.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": ["kind": "HogQLQuery", "query": query],
            "name": name,
        ])
        return request
    }

    private func run(_ query: String, name: String) async throws -> HogQLResponse {
        let request = try Self.request(for: query, name: name, credential: credential)
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            guard let decoded = try? JSONDecoder().decode(HogQLResponse.self, from: data) else {
                throw AnalyticsError.malformedResponse
            }
            return decoded
        case 401:
            throw AnalyticsError.authenticationFailed(Self.errorMessage(data) ?? "unauthorized")
        case 403:
            throw AnalyticsError.permissionDenied
        default:
            throw AnalyticsError.api(status: response.statusCode, message: Self.errorMessage(data) ?? "no detail")
        }
    }

    /// PostHog's errors are `{"type": "...", "code": "...", "detail": "..."}`
    /// (Django REST framework's envelope).
    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["detail"] as? String
    }

    // MARK: - Days

    /// Every `yyyyMMdd` from `start` to `end` inclusive, both given as
    /// `yyyy-MM-dd`.
    static func days(from start: String, to end: String) -> [String] {
        let first = HogQLResponse.gaDate(start)
        let last = HogQLResponse.gaDate(end)
        guard let startDate = isoParser.date(from: start), first <= last else { return [] }
        var days: [String] = []
        var cursor = startDate
        while true {
            let day = HogQLResponse.gaDate(isoParser.string(from: cursor))
            if day > last || days.count > 400 { break }
            days.append(day)
            cursor = cursor.addingTimeInterval(86_400)
        }
        return days
    }

    /// PostHog only returns days with pageviews. Unlike GA, its numbers are
    /// live, so a missing day really is zero; filling it keeps the sparkline
    /// and the menu bar from showing yesterday's number as today's.
    static func filled(_ points: [PropertyStats.DailyPoint], days: [String]) -> [PropertyStats.DailyPoint] {
        var byDay = Dictionary(points.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        for day in days where byDay[day] == nil {
            byDay[day] = PropertyStats.DailyPoint(date: day, activeUsers: 0, sessions: 0)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// UTC and fixed-length days, so stepping a day at a time can never skip
    /// or repeat one across a daylight-saving change.
    private static let isoParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
