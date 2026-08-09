import Foundation
@testable import MarketPlugin
import PerchKit

enum MarketFixture {
    /// Every directory handed out below, removed together when the test
    /// process exits. Nothing was deleting these, so a full `swift test` run
    /// left one directory per store behind in the system temp directory.
    private static var directories: [URL] = []
    private static let registerCleanup: Void = {
        atexit {
            for url in MarketFixture.directories {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }()

    static func temporaryStorage() -> PluginStorage {
        _ = registerCleanup
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketTests-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        return PluginStorage(directory: directory)
    }
}

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
    /// Runs synchronously inside `search`, before it returns — the way tests
    /// simulate the MainActor servicing other work during the `await`, e.g.
    /// a watch being paused, edited, or deleted mid-poll.
    var onSearch: (() -> Void)?
    /// Called inside `search`, before it returns. Lets a test suspend a poll
    /// in flight.
    var beforeReturning: (() async -> Void)?
    private(set) var calls: [Call] = []

    init(results: [ScrapedListing] = []) {
        self.results = results
    }

    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        calls.append(Call(query: query, maxPrice: maxPrice, location: location, radiusKm: radiusKm))
        onSearch?()
        if let beforeReturning { await beforeReturning() }
        if let error {
            if failFirstCallOnly { self.error = nil }
            throw error
        }
        return results
    }
}

/// Lets a test hold a fake's `search` open until it chooses to release it.
actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
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
