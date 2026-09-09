import Foundation

/// A fetch that failed, phrased for the panel rather than for a log.
///
/// The cases are deliberately finer-grained than "it didn't work". Collapsing
/// every `URLError` into one message once hid an App Transport Security
/// rejection behind "Couldn't reach", which sent the diagnosis in entirely the
/// wrong direction: the host was reachable and the address was simply http.
public enum ServerError: Error, Equatable, Sendable {
    case unauthorized
    case unreachable(String)
    case timedOut(String)
    case insecureBlocked(String)
    case tlsFailed(String)
    case badStatus(Int)
    case notAnAgent
    case badURL

    public var message: String {
        switch self {
        case .unauthorized:
            "Wrong username or password."
        case .unreachable(let host):
            "Couldn't reach \(host)."
        case .timedOut(let host):
            "\(host) didn't answer in time."
        case .insecureBlocked(let host):
            "macOS blocked the insecure http connection to \(host). Use https."
        case .tlsFailed(let host):
            "Couldn't establish a secure connection to \(host)."
        case .badStatus(let code):
            "The server replied \(code)."
        case .notAnAgent:
            "That address answered, but not with vpsstat data."
        case .badURL:
            "That doesn't look like a web address."
        }
    }

    /// Maps a `URLError` to the closest case. Anything unrecognised stays
    /// `.unreachable`, which is the honest summary of "the request never got a
    /// reply", rather than inventing a more specific cause.
    static func from(_ error: URLError, host: String) -> ServerError {
        switch error.code {
        case .timedOut:
            return .timedOut(host)
        case .appTransportSecurityRequiresSecureConnection:
            return .insecureBlocked(host)
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return .tlsFailed(host)
        default:
            return .unreachable(host)
        }
    }
}
