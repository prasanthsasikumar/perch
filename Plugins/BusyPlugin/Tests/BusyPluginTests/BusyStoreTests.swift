@testable import BusyPlugin
import PerchKit
import XCTest

@MainActor
final class BusyStoreTests: XCTestCase {
    private var storage: PluginStorage!
    private var source: FakeBusynessSource!
    private var clock: FakeClock!
    private var store: BusyStore!

    override func setUp() {
        super.setUp()
        storage = BusyFixture.temporaryStorage()
        source = FakeBusynessSource()
        clock = FakeClock()
        store = BusyStore(storage: storage, source: source, clock: clock.callAsFunction)
    }

    // MARK: - Places

    func testAddingAPlaceTrimsTheQuery() throws {
        let place = try XCTUnwrap(store.addPlace(query: "  lion gym  "))

        XCTAssertEqual(place.query, "lion gym")
        XCTAssertEqual(store.places.map(\.id), [place.id])
    }

    func testABlankQueryIsRefused() {
        XCTAssertNil(store.addPlace(query: "   "))
        XCTAssertTrue(store.places.isEmpty)
    }

    func testDeletingAPlaceDropsItsResultAndFailure() async throws {
        let place = try XCTUnwrap(store.addPlace(query: "gym"))
        await store.refresh()
        XCTAssertNotNil(store.results[place.id])

        store.deletePlace(id: place.id)

        XCTAssertTrue(store.places.isEmpty)
        XCTAssertNil(store.results[place.id])
        XCTAssertNil(store.failures[place.id])
    }

    // MARK: - Persistence

    func testPlacesResultsAndSettingsSurviveAReload() async throws {
        let place = try XCTUnwrap(store.addPlace(query: "gym"))
        await store.refresh()
        store.updateSettings(BusySettings(refreshIntervalMinutes: 25))
        store.saveNow()

        let reloaded = BusyStore(storage: storage, source: source, clock: clock.callAsFunction)

        XCTAssertEqual(reloaded.places, [place])
        XCTAssertEqual(reloaded.results[place.id]?.reading, BusyFixture.liveReading)
        XCTAssertEqual(reloaded.results[place.id]?.fetchedAt, clock.now)
        XCTAssertEqual(reloaded.settings.refreshIntervalMinutes, 25)
        XCTAssertEqual(reloaded.lastRefreshed, clock.now)
    }

    func testAnUnreadableFileIsReportedNotSilentlyEmptied() throws {
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storage.url(named: "busy.json"))

        let store = BusyStore(storage: storage, source: source, clock: clock.callAsFunction)

        XCTAssertNotNil(store.loadFailureNotice)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url(named: "busy.json.bak").path))
    }

    // MARK: - Refresh

    func testRefreshRecordsAResultPerPlace() async throws {
        let gym = try XCTUnwrap(store.addPlace(query: "gym"))
        let cafe = try XCTUnwrap(store.addPlace(query: "cafe"))

        await store.refresh()

        XCTAssertEqual(source.queries, ["gym", "cafe"])
        XCTAssertEqual(store.results[gym.id]?.reading, BusyFixture.liveReading)
        XCTAssertEqual(store.results[cafe.id]?.reading, BusyFixture.liveReading)
        XCTAssertEqual(store.lastRefreshed, clock.now)
        XCTAssertFalse(store.isRefreshing)
    }

    func testAFailureIsRecordedAndThePreviousResultKept() async throws {
        let gym = try XCTUnwrap(store.addPlace(query: "gym"))
        await store.refresh()
        let first = store.results[gym.id]

        source.error = BusyError.notFound
        clock.advance(600)
        await store.refresh()

        XCTAssertEqual(store.results[gym.id], first)
        XCTAssertEqual(store.failures[gym.id], BusyError.notFound.message)
    }

    func testASuccessClearsAnEarlierFailure() async throws {
        let gym = try XCTUnwrap(store.addPlace(query: "gym"))
        source.error = BusyError.failed("timed out")
        await store.refresh()
        XCTAssertNotNil(store.failures[gym.id])

        source.error = nil
        await store.refresh()

        XCTAssertNil(store.failures[gym.id])
    }

    func testAnUnexpectedErrorGetsAPlainMessage() async throws {
        struct Weird: Error {}
        let gym = try XCTUnwrap(store.addPlace(query: "gym"))
        source.error = Weird()

        await store.refresh()

        XCTAssertEqual(store.failures[gym.id], "Something went wrong while checking.")
    }

    func testAPlaceDeletedMidFetchIsNotResurrected() async throws {
        let gym = try XCTUnwrap(store.addPlace(query: "gym"))
        source.onFetch = { [store] _ in store?.deletePlace(id: gym.id) }

        await store.refresh()

        XCTAssertTrue(store.places.isEmpty)
        XCTAssertNil(store.results[gym.id])
        XCTAssertNil(store.failures[gym.id])
    }

    func testRefreshIfStaleSkipsFreshNumbers() async throws {
        store.addPlace(query: "gym")
        await store.refresh()
        XCTAssertEqual(source.queries.count, 1)

        clock.advance(60)
        await store.refreshIfStale(maxAge: 180)
        XCTAssertEqual(source.queries.count, 1)

        clock.advance(200)
        await store.refreshIfStale(maxAge: 180)
        XCTAssertEqual(source.queries.count, 2)
    }

    func testAPlaceWithNoResultYetIsAlwaysStale() async throws {
        store.addPlace(query: "gym")
        source.error = BusyError.failed("timed out")
        await store.refresh()
        XCTAssertEqual(store.lastRefreshed, clock.now)

        // Fresh by the clock, but the place has never had numbers.
        await store.refreshIfStale(maxAge: 180)

        XCTAssertEqual(source.queries.count, 2)
    }

    func testTheMenuBarShowsTheFirstPlacesLiveFigure() async throws {
        XCTAssertNil(store.menuBarPercent)
        store.addPlace(query: "gym")
        XCTAssertNil(store.menuBarPercent)

        await store.refresh()

        XCTAssertEqual(store.menuBarPercent, 78)
    }
}
