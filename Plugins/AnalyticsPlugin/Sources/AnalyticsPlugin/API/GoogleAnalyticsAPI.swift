import Foundation

/// What the store needs from an analytics backend, and nothing else.
///
/// Named for Google because GA came first; PostHog fills the same shape, with
/// sites standing in for properties.
///
/// The seam that keeps the whole test suite offline: `AnalyticsStore` never
/// sees a `URLSession`, so its behaviour — staleness, caching, per-property
/// error isolation — is tested against a stub in memory.
public protocol GoogleAnalyticsAPI: Sendable {
    /// The three reports for one property, as of a given day.
    func stats(for propertyID: String, today: Date) async throws -> PropertyStats

    /// Stats for every watched property at once. GA answers per property, so
    /// the default fans `stats(for:today:)` out concurrently; PostHog keeps
    /// every site in one project and caps concurrent queries at three, so it
    /// answers for all of them in two grouped queries instead.
    func stats(
        for propertyIDs: [String], today: Date
    ) async -> [(String, Result<PropertyStats, AnalyticsError>)]

    /// The trailing week split by source, country, device and so on. Only the
    /// detail window asks for this.
    func breakdown(for propertyID: String, today: Date) async throws -> PropertyBreakdown

    /// Every property the credential can see, via the Admin API.
    func discoverProperties() async throws -> [AnalyticsProperty]

    /// Shown when a property returns 403, so the user knows which account to
    /// grant access to. Empty for a source with no such account.
    var clientEmail: String { get }
}

public extension GoogleAnalyticsAPI {
    func stats(
        for propertyIDs: [String], today: Date
    ) async -> [(String, Result<PropertyStats, AnalyticsError>)] {
        // Concurrently, because one slow property should not hold up the
        // rest and the panel renders each card independently anyway.
        await withTaskGroup(
            of: (String, Result<PropertyStats, AnalyticsError>).self
        ) { group -> [(String, Result<PropertyStats, AnalyticsError>)] in
            for id in propertyIDs {
                group.addTask {
                    do {
                        return (id, .success(try await stats(for: id, today: today)))
                    } catch let error as AnalyticsError {
                        return (id, .failure(error))
                    } catch {
                        return (id, .failure(.malformedResponse))
                    }
                }
            }
            var collected: [(String, Result<PropertyStats, AnalyticsError>)] = []
            for await result in group { collected.append(result) }
            return collected
        }
    }
}
