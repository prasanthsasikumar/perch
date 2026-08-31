import Foundation

/// Everything the plugin persists, in one file.
///
/// Results are kept so the panel opens on the last known numbers rather than
/// a spinner; the footer says how old they are.
struct BusyDocument: Codable, Equatable {
    var places: [Place]
    var results: [UUID: Busyness]
    var settings: BusySettings
    var lastRefreshed: Date?

    static let empty = BusyDocument(places: [], results: [:], settings: .defaults, lastRefreshed: nil)
}
