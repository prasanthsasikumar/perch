@testable import BusyPlugin
import Foundation
import PerchKit

enum BusyFixture {
    /// Every directory handed out below, removed together when the test
    /// process exits.
    private static var directories: [URL] = []
    private static let registerCleanup: Void = {
        atexit {
            for url in BusyFixture.directories {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }()

    static func temporaryStorage() -> PluginStorage {
        _ = registerCleanup
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BusyTests-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        return PluginStorage(directory: directory)
    }

    static let liveReading = BusyReading(
        name: "Lion Gym Kesavadasapuram",
        statusText: "A little busy",
        isLive: true,
        livePercent: 78,
        usualPercent: 61,
        currentHour: 16,
        day: 1,
        hours: [HourBusyness(hour: 15, percent: 50), HourBusyness(hour: 16, percent: 61)]
    )
}

/// A `BusynessSource` whose answers are scripted, so the store can be tested
/// without a browser.
@MainActor
final class FakeBusynessSource: BusynessSource {
    var reading = BusyFixture.liveReading
    var error: Error?
    /// Runs inside `fetch`, before it returns — the way tests simulate the
    /// MainActor servicing other work during the `await`.
    var onFetch: ((String) -> Void)?
    private(set) var queries: [String] = []

    func fetch(query: String) async throws -> BusyReading {
        queries.append(query)
        onFetch?(query)
        if let error { throw error }
        return reading
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
