import Foundation

/// One saved place.
///
/// `query` is whatever the user typed, sent to Google verbatim — the same
/// words they would put in the search box. The name Google answers with
/// lives on the result, not here, so a place is showable before its first
/// fetch and stays showable if a fetch fails.
public struct Place: Identifiable, Codable, Equatable {
    public let id: UUID
    public var query: String
    public let createdAt: Date

    public init(id: UUID = UUID(), query: String, createdAt: Date = .now) {
        self.id = id
        self.query = query
        self.createdAt = createdAt
    }
}
