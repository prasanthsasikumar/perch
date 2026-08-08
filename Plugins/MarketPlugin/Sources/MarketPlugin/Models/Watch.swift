import Foundation

/// One saved search.
///
/// `location` and `radiusKm` are copied from settings when the watch is
/// created rather than read live, so changing the default later does not
/// silently move searches the user already set up.
public struct Watch: Identifiable, Codable, Equatable {
    public let id: UUID
    public var query: String
    public var maxPrice: Int?
    public var location: String
    public var radiusKm: Int
    public var paused: Bool
    public let createdAt: Date
    public var lastCheckedAt: Date?
    public var consecutiveFailures: Int
    /// `.distantPast` means "due now", which is what a new watch wants.
    public var nextCheckAt: Date

    public init(
        id: UUID = UUID(),
        query: String,
        maxPrice: Int?,
        location: String,
        radiusKm: Int,
        paused: Bool = false,
        createdAt: Date = .now,
        lastCheckedAt: Date? = nil,
        consecutiveFailures: Int = 0,
        nextCheckAt: Date = .distantPast
    ) {
        self.id = id
        self.query = query
        self.maxPrice = maxPrice
        self.location = location
        self.radiusKm = radiusKm
        self.paused = paused
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.consecutiveFailures = consecutiveFailures
        self.nextCheckAt = nextCheckAt
    }
}
