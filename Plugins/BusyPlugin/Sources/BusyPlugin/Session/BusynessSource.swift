import Foundation

/// Where readings come from.
///
/// Nothing above this protocol knows about WKWebView, Google, or HTML. The
/// production conformance renders a search page; every test uses a fake.
@MainActor
public protocol BusynessSource {
    func fetch(query: String) async throws -> BusyReading
}

public enum BusyError: Error, Equatable {
    /// The page rendered, but had no popular-times widget: Google has no
    /// busyness data for this place, or the query matched nothing. Retrying
    /// harder does not help; rewording the query might.
    case notFound
    /// Google redirected to its cookie-consent page. Nothing in the plugin
    /// can click through it.
    case consentWall
    /// Navigation failed or timed out. Worth retrying later.
    case failed(String)

    /// What the panel shows under the place.
    public var message: String {
        switch self {
        case .notFound:
            "Google has no busyness data for this — try wording it the way Maps names the place."
        case .consentWall:
            "Google is asking for cookie consent, which Perch can't answer yet."
        case .failed(let reason):
            reason
        }
    }
}
