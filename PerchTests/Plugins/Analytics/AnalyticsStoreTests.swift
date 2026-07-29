import PerchKit
import XCTest
@testable import AnalyticsPlugin

@MainActor
final class AnalyticsStoreTests: XCTestCase {
    private let siteA = AnalyticsProperty(id: "111", displayName: "a.example")
    private let siteB = AnalyticsProperty(id: "222", displayName: "b.example")

    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        directory: URL = Fixture.temporaryDirectory(),
        credentials: InMemoryCredentialStore,
        api: StubAnalyticsAPI = StubAnalyticsAPI()
    ) -> AnalyticsStore {
        AnalyticsStore(
            storage: PluginStorage(directory: directory),
            credentials: credentials,
            apiFactory: { _ in api },
            now: { self.clock }
        )
    }

    private func configuredCredentials() throws -> InMemoryCredentialStore {
        InMemoryCredentialStore(seeded: try ServiceAccount(keyFile: try Fixture.serviceAccountJSON()))
    }

    // MARK: - Credentials

    func testStartsUnconfiguredWithNoStoredKey() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(store.credentialFailure, .notConfigured)
    }

    func testImportingAKeyConfiguresTheStore() throws {
        let credentials = InMemoryCredentialStore()
        let store = makeStore(credentials: credentials)

        try store.importCredential(keyFile: try Fixture.serviceAccountJSON())

        XCTAssertTrue(store.isConfigured)
        XCTAssertNil(store.credentialFailure)
        // Persisted, so the next launch does not ask again.
        XCTAssertNotNil(try credentials.load())
    }

    func testABadKeyFileIsRejectedWithoutBeingStored() throws {
        let credentials = InMemoryCredentialStore()
        let store = makeStore(credentials: credentials)

        XCTAssertThrowsError(try store.importCredential(keyFile: Data("nope".utf8)))
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(try credentials.load())
    }

    /// Numbers fetched with a credential the user just revoked must not keep
    /// sitting in the panel as though they were live.
    func testRemovingTheCredentialClearsTheNumbers() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])
        await store.refresh()
        XCTAssertNotNil(store.stats["111"])

        try store.removeCredential()

        XCTAssertFalse(store.isConfigured)
        XCTAssertTrue(store.stats.isEmpty)
        XCTAssertNil(store.lastRefreshed)
        XCTAssertEqual(store.credentialFailure, .notConfigured)
    }

    // MARK: - Refresh

    func testRefreshStoresStatsPerProperty() async throws {
        let api = StubAnalyticsAPI(results: [
            "111": .success(Fixture.stats(users: 312, previousUsers: 273)),
            "222": .success(Fixture.stats(users: 88, previousUsers: 72)),
        ])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA, siteB])

        await store.refresh()

        XCTAssertEqual(store.stats["111"]?.currentWeek.activeUsers, 312)
        XCTAssertEqual(store.stats["222"]?.currentWeek.activeUsers, 88)
        XCTAssertTrue(store.failures.isEmpty)
        XCTAssertEqual(store.lastRefreshed, clock)
    }

    /// The reason failures are per property at all: one site the account was
    /// never granted must not blank the site it was.
    func testOnePropertyFailingLeavesTheOthersAlone() async throws {
        let api = StubAnalyticsAPI(results: [
            "111": .success(Fixture.stats(users: 312)),
            "222": .failure(.permissionDenied),
        ])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA, siteB])

        await store.refresh()

        XCTAssertEqual(store.stats["111"]?.currentWeek.activeUsers, 312)
        XCTAssertNil(store.failures["111"])
        XCTAssertEqual(store.failures["222"], .permissionDenied)
        XCTAssertNil(store.credentialFailure)
    }

    /// Showing yesterday's numbers and saying so beats blanking the card
    /// because the wifi dropped.
    func testCachedNumbersSurviveAFailedRefresh() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats(users: 312))])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])
        await store.refresh()
        let firstRefresh = store.lastRefreshed

        api.setResult(.failure(.offline), for: "111")
        clock = clock.addingTimeInterval(3600)
        await store.refresh()

        XCTAssertEqual(store.stats["111"]?.currentWeek.activeUsers, 312)
        XCTAssertEqual(store.failures["111"], .offline)
        // Unmoved, so "updated an hour ago" stays honest about what is shown.
        XCTAssertEqual(store.lastRefreshed, firstRefresh)
    }

    /// A dead credential breaks every property at once, so it is a banner
    /// rather than the same message repeated on every card.
    func testAuthenticationFailureIsRaisedAsACredentialProblem() async throws {
        let api = StubAnalyticsAPI(results: ["111": .failure(.authenticationFailed("invalid_grant"))])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])

        await store.refresh()

        XCTAssertEqual(store.credentialFailure, .authenticationFailed("invalid_grant"))
    }

    func testRefreshDoesNothingWithoutACredential() async {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let store = makeStore(credentials: InMemoryCredentialStore(), api: api)
        store.setProperties([siteA])

        await store.refresh()

        XCTAssertEqual(api.callCount, 0)
        XCTAssertEqual(store.credentialFailure, .notConfigured)
    }

    // MARK: - Staleness

    func testNeedsRefreshWithNoCache() throws {
        let store = makeStore(credentials: try configuredCredentials())
        XCTAssertTrue(store.needsRefresh(maxAge: 60))
    }

    func testStalenessIsMeasuredFromTheLastSuccessfulRefresh() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])
        await store.refresh()

        XCTAssertFalse(store.needsRefresh(maxAge: 60))
        clock = clock.addingTimeInterval(61)
        XCTAssertTrue(store.needsRefresh(maxAge: 60))
    }

    /// Opening the panel twice in quick succession should not hit the API
    /// twice.
    func testRefreshIfStaleSkipsAFreshCache() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])

        await store.refreshIfStale(maxAge: 60)
        await store.refreshIfStale(maxAge: 60)

        XCTAssertEqual(api.callCount, 1)
    }

    // MARK: - Properties

    func testSettingPropertiesDropsStatsForOnesNoLongerWatched() async throws {
        let api = StubAnalyticsAPI(results: [
            "111": .success(Fixture.stats()),
            "222": .success(Fixture.stats()),
        ])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA, siteB])
        await store.refresh()

        store.setProperties([siteA])

        XCTAssertNotNil(store.stats["111"])
        XCTAssertNil(store.stats["222"])
    }

    func testRemovingThePrimaryPropertyPromotesAnother() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        store.setProperties([siteA, siteB])
        store.primaryPropertyID = siteA.id

        store.removeProperty(id: siteA.id)

        XCTAssertEqual(store.primaryPropertyID, siteB.id)
        XCTAssertEqual(store.primaryProperty, siteB)
    }

    func testAddingADuplicatePropertyIsIgnored() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        store.addProperty(siteA)
        store.addProperty(siteA)
        XCTAssertEqual(store.properties, [siteA])
    }

    // MARK: - Menu bar

    func testMenuBarShowsTheLatestDayForThePrimaryProperty() async throws {
        var stats = Fixture.stats()
        stats.daily = [
            PropertyStats.DailyPoint(date: "20260726", activeUsers: 10, sessions: 20),
            PropertyStats.DailyPoint(date: "20260727", activeUsers: 42, sessions: 55),
        ]
        let api = StubAnalyticsAPI(results: ["111": .success(stats), "222": .success(Fixture.stats())])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA, siteB])
        store.primaryPropertyID = siteA.id

        await store.refresh()

        XCTAssertEqual(store.menuBarUsers, 42)
    }

    /// A property reporting in Asia/Singapore is already on tomorrow's date
    /// by a New York evening. Keying off the Mac's clock would show yesterday
    /// while GA's own dashboard showed today.
    func testMenuBarUsesGAsLatestDayNotTheMacsToday() async throws {
        var stats = Fixture.stats()
        stats.daily = [
            PropertyStats.DailyPoint(date: "20260728", activeUsers: 10, sessions: 20),
            PropertyStats.DailyPoint(date: "20260729", activeUsers: 13, sessions: 18),
        ]
        let api = StubAnalyticsAPI(results: ["111": .success(stats)])
        // The store's clock says the 28th; GA has already rolled to the 29th.
        clock = ISO8601DateFormatter().date(from: "2026-07-28T20:00:00Z")!
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])

        await store.refresh()

        XCTAssertEqual(store.menuBarUsers, 13)
    }

    func testMenuBarHasNothingToShowBeforeAnyFetch() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        XCTAssertNil(store.menuBarUsers)
    }

    // MARK: - Persistence

    /// What lets the panel open on real numbers instead of a spinner.
    func testCacheSurvivesRelaunch() async throws {
        let directory = Fixture.temporaryDirectory()
        let credentials = try configuredCredentials()
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats(users: 312))])

        let first = makeStore(directory: directory, credentials: credentials, api: api)
        first.setProperties([siteA, siteB])
        first.primaryPropertyID = siteB.id
        await first.refresh()
        first.saveNow()

        let second = makeStore(directory: directory, credentials: credentials, api: api)

        XCTAssertEqual(second.properties, [siteA, siteB])
        XCTAssertEqual(second.stats["111"]?.currentWeek.activeUsers, 312)
        XCTAssertEqual(second.primaryPropertyID, siteB.id)
        XCTAssertEqual(second.lastRefreshed, first.lastRefreshed)
    }

    /// Everything cached is refetchable, so a corrupt file is worth starting
    /// over from rather than reporting.
    func testACorruptCacheStartsEmptyRatherThanThrowing() throws {
        let directory = Fixture.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("analytics.json"))

        let store = makeStore(directory: directory, credentials: InMemoryCredentialStore())

        XCTAssertTrue(store.properties.isEmpty)
        XCTAssertNil(store.lastRefreshed)
    }
}
