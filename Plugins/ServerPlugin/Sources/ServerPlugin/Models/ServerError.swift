import Foundation

/// A fetch that failed, phrased for the panel rather than for a log.
public enum ServerError: Error, Equatable, Sendable {
    case unauthorized
    case unreachable(String)
    case badStatus(Int)
    case notAnAgent
    case badURL

    public var message: String {
        switch self {
        case .unauthorized:
            "Wrong username or password."
        case .unreachable(let host):
            "Couldn't reach \(host)."
        case .badStatus(let code):
            "The server replied \(code)."
        case .notAnAgent:
            "That address answered, but not with vpsstat data."
        case .badURL:
            "That doesn't look like a web address."
        }
    }
}
