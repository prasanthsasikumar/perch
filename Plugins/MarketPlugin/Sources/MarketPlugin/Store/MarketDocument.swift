import Foundation

/// Everything the plugin persists, in one file.
///
/// One document rather than three keeps writes atomic: a save can never leave
/// watches and their listings disagreeing about what exists.
struct MarketDocument: Codable, Equatable {
    var watches: [Watch]
    var listings: [Listing]
    var settings: MarketSettings

    static let empty = MarketDocument(watches: [], listings: [], settings: .defaults)
}
