import Foundation

/// The real `ListingSource`: a Facebook Marketplace search, through the
/// session's webview.
@MainActor
public struct FacebookListingSource: ListingSource {
    private let session: FacebookSession

    public init(session: FacebookSession) {
        self.session = session
    }

    public func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        guard let url = marketplaceSearchURL(
            query: query, maxPrice: maxPrice, location: location, radiusKm: radiusKm
        ) else {
            // The store refuses to create a watch without a location, so this
            // means a watch predating that rule, or a location edited to
            // nothing. Permanent for this watch, not worth retrying hard —
            // but `failed` is the honest classification, since a human fixing
            // the setting does resolve it.
            throw SearchError.failed("this watch has no location set")
        }
        return try await session.loadResults(url: url)
    }
}
