import Foundation
import PerchKit

enum MarketFixture {
    static func temporaryStorage() -> PluginStorage {
        PluginStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MarketTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}

@testable import MarketPlugin

/// A `ListingSource` whose answers are scripted, so the poller can be tested
/// without a browser.
@MainActor
final class FakeListingSource: ListingSource {
    struct Call: Equatable {
        let query: String
        let maxPrice: Int?
        let location: String
        let radiusKm: Int
    }

    var results: [ScrapedListing] = []
    var error: SearchError?
    /// When set, only the first call fails; later calls succeed.
    var failFirstCallOnly = false
    private(set) var calls: [Call] = []

    init(results: [ScrapedListing] = []) {
        self.results = results
    }

    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        calls.append(Call(query: query, maxPrice: maxPrice, location: location, radiusKm: radiusKm))
        if let error {
            if failFirstCallOnly { self.error = nil }
            throw error
        }
        return results
    }
}

/// A clock the test moves by hand. No test sleeps.
final class FakeClock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func callAsFunction() -> Date { now }

    func advance(_ seconds: TimeInterval) { now += seconds }
}
