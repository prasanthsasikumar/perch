import Foundation

/// The plugin's one door to the network.
///
/// Everything that talks to Google goes through this, so every test in the
/// suite can run with no network and no credentials.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AnalyticsError.malformedResponse
            }
            return (data, http)
        } catch let error as URLError {
            // Being offline is a state the panel draws differently — cached
            // numbers, dimmed — so it must not arrive as an opaque failure.
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .timedOut, .dnsLookupFailed:
                throw AnalyticsError.offline
            default:
                throw AnalyticsError.api(status: error.errorCode, message: error.localizedDescription)
            }
        }
    }
}
