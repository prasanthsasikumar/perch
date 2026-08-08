import Foundation
@testable import MarketPlugin
import PerchKit
import XCTest

@MainActor
final class MarketStoreTests: XCTestCase {
    private func configuredStore(
        storage: PluginStorage = MarketFixture.temporaryStorage()
    ) -> MarketStore {
        let store = MarketStore(storage: storage)
        store.updateSettings(MarketSettings(location: "auckland", radiusKm: 50))
        return store
    }

    func testAWatchCannotBeAddedBeforeALocationIsSet() {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())

        XCTAssertFalse(store.canAddWatch)
        XCTAssertNil(store.addWatch(query: "GoPro", maxPrice: 200))
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testAWatchCanBeAddedOnceALocationIsSet() {
        let store = configuredStore()

        XCTAssertTrue(store.canAddWatch)
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)

        XCTAssertEqual(watch?.query, "GoPro")
        XCTAssertEqual(store.watches.count, 1)
    }

    func testANewWatchTakesTheCurrentLocation() {
        let store = configuredStore()

        let watch = store.addWatch(query: "GoPro", maxPrice: 200)

        XCTAssertEqual(watch?.location, "auckland")
        XCTAssertEqual(watch?.radiusKm, 50)
    }

    func testChangingSettingsDoesNotMoveExistingWatches() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)!

        store.updateSettings(MarketSettings(location: "wellington", radiusKm: 20))

        XCTAssertEqual(store.watches.first(where: { $0.id == watch.id })?.location, "auckland")
    }

    func testABlankQueryIsRejected() {
        let store = configuredStore()

        XCTAssertNil(store.addWatch(query: "   ", maxPrice: nil))
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testAQueryIsStoredTrimmed() {
        let store = configuredStore()

        XCTAssertEqual(store.addWatch(query: "  GoPro  ", maxPrice: nil)?.query, "GoPro")
    }

    func testDeletingAWatchRemovesItsListings() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        store.deleteWatch(id: watch.id)

        XCTAssertTrue(store.watches.isEmpty)
        XCTAssertTrue(store.listings(for: watch.id).isEmpty)
    }

    func testRecordReturnsOnlyTheNewOnes() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        let fresh = store.record([scraped("a"), scraped("b")], for: watch.id)

        XCTAssertEqual(fresh.map(\.id), ["b"])
    }

    func testTwoWatchesTrackTheSameListingIndependently() {
        let store = configuredStore()
        let first = store.addWatch(query: "GoPro", maxPrice: nil)!
        let second = store.addWatch(query: "camera", maxPrice: nil)!
        _ = store.record([scraped("a")], for: first.id)

        let fresh = store.record([scraped("a")], for: second.id)

        XCTAssertEqual(fresh.map(\.id), ["a"])
    }

    func testNewlyRecordedListingsAreUnseen() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!

        _ = store.record([scraped("a"), scraped("b")], for: watch.id)

        XCTAssertEqual(store.unseenCount(for: watch.id), 2)
        XCTAssertEqual(store.totalUnseen, 2)
    }

    func testMarkSeenClearsTheCount() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        store.markSeen(watchID: watch.id)

        XCTAssertEqual(store.unseenCount(for: watch.id), 0)
    }

    func testListingsComeBackNewestFirst() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)
        _ = store.record([scraped("b")], for: watch.id)

        XCTAssertEqual(store.listings(for: watch.id).map(\.id), ["b", "a"])
    }

    func testNewestTrimsToTheLimit() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a"), scraped("b"), scraped("c")], for: watch.id)

        XCTAssertEqual(store.newest(for: watch.id, limit: 2).count, 2)
    }

    func testListingsAreCappedPerWatch() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        let many = (0..<(MarketStore.listingsPerWatchCap + 10)).map { scraped("id-\($0)") }

        _ = store.record(many, for: watch.id)

        XCTAssertEqual(store.listings(for: watch.id).count, MarketStore.listingsPerWatchCap)
    }

    func testTheCapDropsTheOldest() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("oldest")], for: watch.id)
        let many = (0..<MarketStore.listingsPerWatchCap).map { scraped("id-\($0)") }

        _ = store.record(many, for: watch.id)

        XCTAssertFalse(store.listings(for: watch.id).contains { $0.id == "oldest" })
    }

    func testStateSurvivesAReload() {
        let storage = MarketFixture.temporaryStorage()
        let store = configuredStore(storage: storage)
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)!
        _ = store.record([scraped("a")], for: watch.id)
        store.saveNow()

        let reloaded = MarketStore(storage: storage)

        XCTAssertEqual(reloaded.watches.map(\.query), ["GoPro"])
        XCTAssertEqual(reloaded.settings.location, "auckland")
        XCTAssertEqual(reloaded.listings(for: watch.id).map(\.id), ["a"])
    }

    func testAFreshStoreStartsEmptyRatherThanFailing() {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())

        XCTAssertTrue(store.watches.isEmpty)
        XCTAssertNil(store.loadFailureNotice)
    }

    func testAnUnreadableDocumentIsReportedRatherThanSwallowed() throws {
        let storage = MarketFixture.temporaryStorage()
        try FileManager.default.createDirectory(
            at: storage.directory, withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: storage.url(named: "market.json"))

        let store = MarketStore(storage: storage)

        XCTAssertNotNil(store.loadFailureNotice)
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testRecordIgnoresAWatchThatNoLongerExists() {
        // Defense in depth: `WatchPoller` re-checks before calling `record`
        // after an `await`, but the store must not depend on every caller
        // remembering to do that — an orphaned entry in `listingsByWatch`
        // outlives the watch in every save from here on.
        let store = configuredStore()
        let ghostID = UUID()

        let fresh = store.record([scraped("a")], for: ghostID)

        XCTAssertTrue(fresh.isEmpty)
        XCTAssertTrue(store.listings(for: ghostID).isEmpty)
    }

    func testASaveFailureSetsTheNotice() throws {
        // A plain file where `PluginStorage` expects a directory makes
        // `createDirectory` throw — a full disk, a permissions problem, or
        // a sandbox denial all fail the same way from the store's side.
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketTests-\(UUID().uuidString)")
        try Data().write(to: path)
        let store = MarketStore(storage: PluginStorage(directory: path))

        store.saveNow()

        XCTAssertNotNil(store.saveFailureNotice)
        try? FileManager.default.removeItem(at: path)
    }

    func testASuccessfulSaveClearsAPriorFailureNotice() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketTests-\(UUID().uuidString)")
        try Data().write(to: path)
        let store = MarketStore(storage: PluginStorage(directory: path))
        store.saveNow()
        XCTAssertNotNil(store.saveFailureNotice)
        try FileManager.default.removeItem(at: path)

        store.saveNow()

        XCTAssertNil(store.saveFailureNotice)
        try? FileManager.default.removeItem(at: path)
    }

    func testUpdatingAWatchReplacesItInPlace() {
        let store = configuredStore()
        var watch = store.addWatch(query: "GoPro", maxPrice: 200)!

        watch.consecutiveFailures = 3
        store.update(watch)

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 3)
    }
}
