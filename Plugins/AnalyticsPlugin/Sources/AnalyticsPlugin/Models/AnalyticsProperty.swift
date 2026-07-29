import Foundation

/// A GA4 property the user has chosen to watch.
public struct AnalyticsProperty: Codable, Identifiable, Hashable, Sendable {
    /// The numeric property id, e.g. `"516503233"`. GA's own APIs take it as
    /// `properties/<id>`; the bare number is what the user sees in GA Admin.
    public let id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Discovery hands back `properties/516503233`; everything else in the
    /// plugin wants the bare id.
    public init(resourceName: String, displayName: String) {
        self.init(
            id: resourceName.hasPrefix("properties/")
                ? String(resourceName.dropFirst("properties/".count))
                : resourceName,
            displayName: displayName
        )
    }
}
