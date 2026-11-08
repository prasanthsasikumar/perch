import Foundation
import XCTest
@testable import AnalyticsPlugin

/// Stands in for the Keychain, so no test writes to the developer's login
/// keychain or prompts for it — and so a test can see exactly what was
/// handed to it.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var _saveCount = 0

    init(seeded: Data? = nil) {
        stored = seeded
    }

    var data: Data? { lock.withLock { stored } }
    var saveCount: Int { lock.withLock { _saveCount } }

    func load() throws -> Data? { lock.withLock { stored } }

    func save(_ data: Data) throws {
        lock.withLock {
            stored = data
            _saveCount += 1
        }
    }

    func remove() throws { lock.withLock { stored = nil } }
}

/// Records requests and answers each from a closure that sees the request,
/// because the PostHog stats queries run concurrently and arrive in either
/// order.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let responder: @Sendable (URLRequest) -> (Data, Int)

    init(responder: @escaping @Sendable (URLRequest) -> (Data, Int)) {
        self.responder = responder
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (body, status) = responder(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

enum PostHogFixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static let credential = PostHogCredential(region: .us, projectID: "12345", apiKey: "phx_testkey1234")

    /// Noon UTC on the day tracking started, in a UTC calendar, so the date
    /// windows are the same on every machine.
    static let today = Date(timeIntervalSince1970: 1_794_139_200) // 2026-11-08T12:00:00Z

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsPluginTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// The `query.query` string out of a recorded request body.
    static func hogQL(in request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = object["query"] as? [String: Any] else { return nil }
        return query["query"] as? String
    }
}
