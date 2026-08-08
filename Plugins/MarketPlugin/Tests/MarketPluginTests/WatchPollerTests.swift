import Foundation
@testable import MarketPlugin
import XCTest

@MainActor
final class WatchPollerTests: XCTestCase {
    private var clock = FakeClock()

    private func makeStore() -> MarketStore {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())
        store.updateSettings(MarketSettings(location: "auckland", radiusKm: 50))
        return store
    }

    private func makePoller(
        store: MarketStore,
        source: FakeListingSource,
        jitter: @escaping (Double, Double) -> Double = { _, _ in 1.0 },
        onFinds: ((UUID, Int) -> Void)? = nil
    ) -> WatchPoller {
        WatchPoller(
            store: store,
            source: source,
            clock: { [clock] in clock.now },
            jitter: jitter,
            onFinds: onFinds
        )
    }

    func testATickSearchesADueWatch() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: 200)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(
            source.calls,
            [.init(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)]
        )
    }

    func testATickReportsTheNewCount() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a"), scraped("b")])
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!

        let results = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.0, watch.id)
        XCTAssertEqual(results.first?.1, 2)
    }

    func testASecondTickReportsNothingNew() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        clock.advance(WatchPoller.minIntervalSeconds * 2)

        let results = await poller.tick()
        XCTAssertTrue(results.isEmpty)
    }

    func testAWatchIsNotRecheckedBeforeTheFloor() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        clock.advance(WatchPoller.minIntervalSeconds - 1)
        _ = await poller.tick()

        XCTAssertEqual(source.calls.count, 1)
    }

    func testAPausedWatchIsSkipped() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.paused = true
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertTrue(source.calls.isEmpty)
    }

    func testWatchesArePolledOneAtATimeInOrder() async {
        let store = makeStore()
        let source = FakeListingSource()
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(source.calls.map(\.query), ["first", "second"])
    }

    func testLowSideJitterCannotScheduleBelowTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 10)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source, jitter: { _, _ in 0.8 }).tick()

        let next = store.watches.first!.nextCheckAt
        XCTAssertGreaterThanOrEqual(
            next.timeIntervalSince(clock.now), WatchPoller.minIntervalSeconds
        )
    }

    func testHighSideJitterIsNotFlattenedToTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 10)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source, jitter: { _, _ in 1.2 }).tick()

        let next = store.watches.first!.nextCheckAt
        XCTAssertGreaterThan(next.timeIntervalSince(clock.now), WatchPoller.minIntervalSeconds)
    }

    func testAFailureBacksTheWatchOff() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 1)
        XCTAssertEqual(poller.state, .backoff)
        XCTAssertEqual(poller.lastError, "boom")
    }

    func testBackoffGrowsWithEachFailure() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()
        let first = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)
        clock.advance(first)
        _ = await poller.tick()
        let second = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)

        XCTAssertGreaterThan(second, first)
    }

    func testBackoffIsCapped() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.consecutiveFailures = 50
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        let delay = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)
        XCTAssertLessThanOrEqual(delay, WatchPoller.maxBackoffSeconds)
    }

    func testASuccessClearsTheFailureCount() async {
        let store = makeStore()
        let source = FakeListingSource()
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.consecutiveFailures = 3
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 0)
    }

    func testAFailureOnOneWatchDoesNotBlockTheNext() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        source.failFirstCallOnly = true
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(source.calls.map(\.query), ["first", "second"])
    }

    func testBeingSignedOutStopsTheWholeTick() async {
        // Polling the second watch would only hit the same wall.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()

        XCTAssertEqual(source.calls.count, 1)
        XCTAssertEqual(poller.state, .signedOut)
    }

    func testBeingSignedOutIsNotCountedAsAFailure() async {
        // It is a human problem, not a flaky scrape — no exponential backoff.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 0)
    }

    func testEveryDueWatchIsPushedPastTheSignInRetry() async {
        // Otherwise the next tick immediately retries a different watch
        // against the same wall.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        for watch in store.watches {
            XCTAssertGreaterThanOrEqual(
                watch.nextCheckAt.timeIntervalSince(clock.now), WatchPoller.signInRetrySeconds
            )
        }
    }

    func testRecoveringFromSignedOutReturnsToIdle() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        source.error = nil
        clock.advance(WatchPoller.minIntervalSeconds * 2)
        _ = await poller.tick()

        XCTAssertEqual(poller.state, .idle)
        XCTAssertNil(poller.lastError)
    }

    func testRecoveringFromBackoffReturnsToIdle() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        source.error = nil
        clock.advance(WatchPoller.maxBackoffSeconds * 2)
        _ = await poller.tick()

        XCTAssertEqual(poller.state, .idle)
    }

    func testTheFindsCallbackFiresPerWatch() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        var seen: [(UUID, Int)] = []

        _ = await makePoller(store: store, source: source, onFinds: { seen.append(($0, $1)) })
            .tick()

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, watch.id)
        XCTAssertEqual(seen.first?.1, 1)
    }

    func testTheCallbackDoesNotFireWhenNothingIsNew() async {
        let store = makeStore()
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        var seen: [(UUID, Int)] = []

        _ = await makePoller(store: store, source: source, onFinds: { seen.append(($0, $1)) })
            .tick()

        XCTAssertTrue(seen.isEmpty)
    }

    func testTheConfiguredIntervalIsHonouredAboveTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 60)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(
            store.watches.first!.nextCheckAt.timeIntervalSince(clock.now), 3600, accuracy: 0.5
        )
    }
}
