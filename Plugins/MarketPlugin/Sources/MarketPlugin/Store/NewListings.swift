import Foundation

/// A listing as it comes off the page, before it belongs to a watch.
public struct ScrapedListing: Equatable, Sendable {
    public let id: String
    public let title: String
    public let price: String
    public let location: String
    public let url: URL
    public let imageURL: URL?

    public init(
        id: String,
        title: String,
        price: String,
        location: String,
        url: URL,
        imageURL: URL?
    ) {
        self.id = id
        self.title = title
        self.price = price
        self.location = location
        self.url = url
        self.imageURL = imageURL
    }
}

/// The listings in `fetched` that are not already in `seenIDs`, deduplicated.
///
/// Fetch order is preserved and the first of any duplicate pair wins, so the
/// freshest scrape of a listing is the one recorded. This is the one piece of
/// logic whose failure a user would actually notice — as a missed find, or as
/// the same listing announced twice.
public func newListings(
    _ fetched: [ScrapedListing], seenIDs: Set<String>
) -> [ScrapedListing] {
    var already = seenIDs
    var result: [ScrapedListing] = []
    for listing in fetched where !already.contains(listing.id) {
        already.insert(listing.id)
        result.append(listing)
    }
    return result
}
