import Foundation

/// A `ListingSource` that finds nothing.
///
/// Plan 1 ships this so the tab is real and usable before any Facebook code
/// exists. Plan 2 replaces it with the WKWebView implementation, and this type
/// goes away with it.
@MainActor
public struct StubListingSource: ListingSource {
    public init() {}

    public func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        []
    }
}
