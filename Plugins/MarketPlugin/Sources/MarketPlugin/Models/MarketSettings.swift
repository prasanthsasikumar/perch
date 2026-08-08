import Foundation

/// Settings shared by every watch.
///
/// `location` has no default on purpose. Facebook scopes marketplace searches
/// to a city, and a wrong city returns nothing just as silently as no city —
/// so the user is asked rather than guessed at.
public struct MarketSettings: Codable, Equatable {
    public var location: String?
    public var radiusKm: Int
    public var pollIntervalMinutes: Int
    public var notificationsEnabled: Bool

    public init(
        location: String? = nil,
        radiusKm: Int = 50,
        pollIntervalMinutes: Int = 15,
        notificationsEnabled: Bool = true
    ) {
        self.location = location
        self.radiusKm = radiusKm
        self.pollIntervalMinutes = pollIntervalMinutes
        self.notificationsEnabled = notificationsEnabled
    }

    public static let defaults = MarketSettings()
}
