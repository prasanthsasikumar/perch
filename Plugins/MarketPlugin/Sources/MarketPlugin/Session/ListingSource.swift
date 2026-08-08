import Foundation

/// Where listings come from.
///
/// The whole point of this protocol is that nothing above it knows about
/// WKWebView, Facebook, or HTML. Plan 2 implements it against a real webview;
/// every test in this plan uses a fake.
@MainActor
public protocol ListingSource {
    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing]
}

public enum SearchError: Error, Equatable {
    /// The Facebook session is gone. A human has to sign in; retrying harder
    /// does not help, so this must never be treated as a flaky scrape.
    case signedOut
    /// The search did not complete. Worth retrying later.
    case failed(String)
}
