import Foundation

/// One listing found for one watch.
///
/// `id` is Facebook's listing id, and the pair (`watchID`, `id`) is what
/// "already found" means — two watches can legitimately both find the same
/// listing and each should report it once.
public struct Listing: Identifiable, Codable, Equatable {
    public let id: String
    public let watchID: UUID
    public var title: String
    public var price: String
    public var location: String
    public var url: URL
    public var imageURL: URL?
    public let firstSeenAt: Date
    /// Whether the user has looked at it — distinct from having fetched it.
    public var seen: Bool

    public init(
        id: String,
        watchID: UUID,
        title: String,
        price: String,
        location: String,
        url: URL,
        imageURL: URL?,
        firstSeenAt: Date = .now,
        seen: Bool = false
    ) {
        self.id = id
        self.watchID = watchID
        self.title = title
        self.price = price
        self.location = location
        self.url = url
        self.imageURL = imageURL
        self.firstSeenAt = firstSeenAt
        self.seen = seen
    }
}
