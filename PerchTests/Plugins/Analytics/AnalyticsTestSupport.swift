import Foundation
@testable import AnalyticsPlugin

// MARK: - Credentials

/// Stands in for the Keychain so no test writes to the developer's login
/// keychain — or prompts them for it.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    init(seeded: ServiceAccount? = nil) {
        stored = seeded.flatMap { try? JSONEncoder().encode($0) }
    }

    func load() throws -> Data? {
        lock.withLock { stored }
    }

    func save(_ data: Data) throws {
        lock.withLock { stored = data }
    }

    func remove() throws {
        lock.withLock { stored = nil }
    }
}

// MARK: - API

/// A `GoogleAnalyticsAPI` whose answers are scripted per property.
final class StubAnalyticsAPI: GoogleAnalyticsAPI, @unchecked Sendable {
    let clientEmail: String

    private let lock = NSLock()
    private var results: [String: Result<PropertyStats, AnalyticsError>]
    private var discovery: Result<[AnalyticsProperty], AnalyticsError>
    private var _callCount = 0

    init(
        clientEmail: String = "perch@example.iam.gserviceaccount.com",
        results: [String: Result<PropertyStats, AnalyticsError>] = [:],
        discovery: Result<[AnalyticsProperty], AnalyticsError> = .success([])
    ) {
        self.clientEmail = clientEmail
        self.results = results
        self.discovery = discovery
    }

    var callCount: Int { lock.withLock { _callCount } }

    func setResult(_ result: Result<PropertyStats, AnalyticsError>, for id: String) {
        lock.withLock { results[id] = result }
    }

    func stats(for propertyID: String, today: Date) async throws -> PropertyStats {
        let result: Result<PropertyStats, AnalyticsError>? = lock.withLock {
            _callCount += 1
            return results[propertyID]
        }
        switch result {
        case .success(let stats): return stats
        case .failure(let error): throw error
        case nil: throw AnalyticsError.permissionDenied
        }
    }

    func discoverProperties() async throws -> [AnalyticsProperty] {
        switch lock.withLock({ discovery }) {
        case .success(let properties): return properties
        case .failure(let error): throw error
        }
    }
}

// MARK: - Transport

/// Records requests and replays scripted responses, so the token provider can
/// be tested without a network.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var responder: @Sendable (Int) -> (Data, Int)

    /// - Parameter responder: called with the zero-based request index,
    ///   returning a body and a status code.
    init(responder: @escaping @Sendable (Int) -> (Data, Int)) {
        self.responder = responder
    }

    convenience init(body: Data, status: Int = 200) {
        self.init(responder: { _ in (body, status) })
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index: Int = lock.withLock {
            _requests.append(request)
            return _requests.count - 1
        }
        let (body, status) = responder(index)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

// MARK: - Fixtures

enum Fixture {
    /// A GA4 key file with a real (throwaway) RSA key, generated once per run.
    static func serviceAccountJSON(
        email: String = "perch@example.iam.gserviceaccount.com"
    ) throws -> Data {
        let object: [String: Any] = [
            "type": "service_account",
            "project_id": "perch-test",
            "private_key_id": "abc123",
            "private_key": try RSATestKey.pkcs8PEM(),
            "client_email": email,
            "client_id": "1234567890",
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func stats(users: Double = 100, previousUsers: Double = 50) -> PropertyStats {
        PropertyStats(
            last30Days: PropertyStats.Totals(activeUsers: users * 4, sessions: users * 6),
            currentWeek: PropertyStats.Totals(activeUsers: users, sessions: users * 2),
            previousWeek: PropertyStats.Totals(activeUsers: previousUsers, sessions: previousUsers * 2),
            daily: [
                PropertyStats.DailyPoint(date: "20260726", activeUsers: 10, sessions: 20),
                PropertyStats.DailyPoint(date: "20260727", activeUsers: 15, sessions: 25),
            ]
        )
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
    }
}
