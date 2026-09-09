import Foundation

/// Reads `/api/now` over HTTP with optional basic auth.
///
/// The credential goes on the request as an `Authorization` header rather than
/// through `URLCredential` and the auth-challenge delegate: the agent sits
/// behind Caddy, which answers an unauthenticated request with a 401 every
/// time, and pre-emptive auth avoids paying two round trips on a link where
/// one already costs a quarter of a second.
public struct HTTPSnapshotSource: SnapshotSource {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            // The agent sets no-store anyway; saying so here means a flaky
            // link cannot serve a stale reading as if it were current.
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetch(_ request: SnapshotRequest) async throws -> HostSnapshot {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let username = request.username, !username.isEmpty, let password = request.password {
            let pair = Data("\(username):\(password)".utf8).base64EncodedString()
            urlRequest.setValue("Basic \(pair)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        let host = request.url.host ?? "the server"
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            // Distinguish the failures that have different fixes: a blocked
            // cleartext connection is not the same problem as a dead host.
            throw ServerError.from(error, host: host)
        } catch {
            throw ServerError.unreachable(host)
        }

        guard let http = response as? HTTPURLResponse else { throw ServerError.notAnAgent }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw ServerError.unauthorized
        default:
            throw ServerError.badStatus(http.statusCode)
        }

        do {
            return try Self.decoder.decode(HostSnapshot.self, from: data)
        } catch {
            // A 200 that will not decode almost always means the URL points at
            // something else entirely — someone's homepage, a login form — and
            // saying "not vpsstat data" is more use than a decoding error.
            throw ServerError.notAnAgent
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
