import Foundation

/// What the store needs from Google, and nothing else.
///
/// The seam that keeps the whole test suite offline: `AnalyticsStore` never
/// sees a `URLSession`, so its behaviour — staleness, caching, per-property
/// error isolation — is tested against a stub in memory.
public protocol GoogleAnalyticsAPI: Sendable {
    /// The three reports for one property, as of a given day.
    func stats(for propertyID: String, today: Date) async throws -> PropertyStats

    /// Every property the credential can see, via the Admin API.
    func discoverProperties() async throws -> [AnalyticsProperty]

    /// Shown when a property returns 403, so the user knows which account to
    /// grant access to.
    var clientEmail: String { get }
}
