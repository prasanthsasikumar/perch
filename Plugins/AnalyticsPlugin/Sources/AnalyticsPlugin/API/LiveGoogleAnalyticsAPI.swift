import Foundation

/// GA4 over plain HTTPS: three `runReport` calls per property against the Data
/// API, and `accountSummaries` against the Admin API.
public struct LiveGoogleAnalyticsAPI: GoogleAnalyticsAPI {
    private static let dataHost = "https://analyticsdata.googleapis.com/v1beta"
    private static let adminHost = "https://analyticsadmin.googleapis.com/v1beta"

    private let tokens: GoogleTokenProvider
    private let transport: HTTPTransport
    private let calendar: Calendar

    public let clientEmail: String

    public init(
        account: ServiceAccount,
        transport: HTTPTransport = URLSessionTransport(),
        calendar: Calendar = .current
    ) {
        self.tokens = GoogleTokenProvider(account: account, transport: transport)
        self.transport = transport
        self.calendar = calendar
        self.clientEmail = account.clientEmail
    }

    // MARK: - Reports

    public func stats(for propertyID: String, today: Date) async throws -> PropertyStats {
        let windows = DateWindows(today: today, calendar: calendar)

        // Concurrent because the three reports are independent and the panel
        // waits on all of them; serially this is three round trips of latency
        // for no reason.
        async let totals = runReport(propertyID, body: [
            "dateRanges": [range(.last30Days)],
            "metrics": metrics(["activeUsers", "sessions", "screenPageViews",
                                "bounceRate", "averageSessionDuration"]),
        ])
        // Both weeks in one request. GA tags each row with which range it came
        // from, so this replaces the two calls the Python script makes.
        async let weeks = runReport(propertyID, body: [
            "dateRanges": [range(windows.currentWeek), range(windows.previousWeek)],
            "metrics": metrics(["activeUsers", "sessions", "screenPageViews"]),
        ])
        async let daily = runReport(propertyID, body: [
            "dateRanges": [range(.last7Days)],
            "dimensions": [["name": "date"]],
            "metrics": metrics(["activeUsers", "sessions"]),
            "orderBys": [["dimension": ["dimensionName": "date"]]],
        ])

        let (totalsReport, weeksReport, dailyReport) = try await (totals, weeks, daily)
        return PropertyStats(
            last30Days: totalsReport.totals(),
            currentWeek: weeksReport.totals(forDateRange: 0),
            previousWeek: weeksReport.totals(forDateRange: 1),
            daily: dailyReport.dailyPoints()
        )
    }

    public func discoverProperties() async throws -> [AnalyticsProperty] {
        struct Summaries: Decodable {
            struct Account: Decodable {
                struct Property: Decodable {
                    let property: String
                    let displayName: String?
                }
                let propertySummaries: [Property]?
            }
            let accountSummaries: [Account]?
        }

        var request = URLRequest(url: URL(string: "\(Self.adminHost)/accountSummaries?pageSize=200")!)
        request.httpMethod = "GET"
        let data = try await authorized(request)

        guard let decoded = try? JSONDecoder().decode(Summaries.self, from: data) else {
            throw AnalyticsError.malformedResponse
        }
        return (decoded.accountSummaries ?? [])
            .flatMap { $0.propertySummaries ?? [] }
            .map { AnalyticsProperty(resourceName: $0.property, displayName: $0.displayName ?? $0.property) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Requests

    private func runReport(_ propertyID: String, body: [String: Any]) async throws -> RunReportResponse {
        var request = URLRequest(url: URL(string: "\(Self.dataHost)/properties/\(propertyID):runReport")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await authorized(request)
        guard let decoded = try? JSONDecoder().decode(RunReportResponse.self, from: data) else {
            throw AnalyticsError.malformedResponse
        }
        return decoded
    }

    /// Attaches the bearer token and turns Google's error envelope into an
    /// `AnalyticsError`.
    private func authorized(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            // The token was rejected rather than merely expired, so holding on
            // to it would fail every subsequent call the same way.
            await tokens.invalidate()
            throw AnalyticsError.authenticationFailed(Self.errorMessage(data) ?? "unauthorized")
        case 403:
            // Google returns 403 both for "you can't see this property" and
            // for "this API was never enabled", and the fixes are in entirely
            // different consoles.
            if Self.errorReason(data) == "SERVICE_DISABLED" {
                throw AnalyticsError.apiNotEnabled(
                    Self.errorMessage(data) ?? "That Google API is not enabled for this project."
                )
            }
            throw AnalyticsError.permissionDenied
        default:
            throw AnalyticsError.api(
                status: response.statusCode,
                message: Self.errorMessage(data) ?? "no detail"
            )
        }
    }

    // MARK: - Bodies

    private func range(_ range: GADateRange) -> [String: String] {
        ["startDate": range.startDate, "endDate": range.endDate]
    }

    private func metrics(_ names: [String]) -> [[String: String]] {
        names.map { ["name": $0] }
    }

    /// Google's REST errors are `{"error":{"code":403,"message":"…"}}`.
    private static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    /// `error.details[].reason`, where Google puts the machine-readable cause.
    private static func errorReason(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let details = error["details"] as? [[String: Any]] else { return nil }
        return details.compactMap { $0["reason"] as? String }.first
    }
}
