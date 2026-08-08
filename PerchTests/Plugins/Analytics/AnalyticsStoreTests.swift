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

    /// The defect this fix removes: constructing a store used to read the
    /// Keychain as a side effect of `init`, which fired every time the
    /// `Analytics` plugin was built — including with the plugin switched off,
    /// and including under an XCTest host — and Perch's ad-hoc signature
    /// changes on every rebuild, so every launch re-triggered the Keychain's
    /// "Perch wants to use your confidential information" prompt.
    func testConstructingAStoreDoesNotReadTheCredentialStore() throws {
        let credentials = try configuredCredentials()

        _ = makeStore(credentials: credentials)

        XCTAssertEqual(credentials.loadCount, 0)
    }

    /// `isConfigured` is one of the two places (alongside `refresh()`) that
    /// must trigger the lazy load, since the panel and the settings pane both
    /// read it synchronously in `body` to decide what to show — there is no
    /// later async step where a load could still land in time.
    func testIsConfiguredOnAStoreWithASeededCredentialStillReportsTrue() throws {
        let store = makeStore(credentials: try configuredCredentials())

        XCTAssertTrue(store.isConfigured)
    }

    /// The Keychain read is guarded by `didLoadCredential` so it happens at
    /// most once no matter how many times the panel or settings pane ask.
    func testTheCredentialIsReadAtMostOnceAcrossSeveralAccesses() throws {
        let credentials = try configuredCredentials()
        let store = makeStore(credentials: credentials)

        _ = store.isConfigured
        _ = store.clientEmail
        _ = store.isConfigured

        XCTAssertEqual(credentials.loadCount, 1)
    }

    /// Importing a credential must leave `didLoadCredential` in a state where
    /// a later read reports the freshly imported credential rather than going
    /// back to the Keychain — which, on a store that never lazily loaded
    /// beforehand, would otherwise clobber what was just imported.
    func testImportingThenReadingIsConfiguredReflectsTheImportedCredentialNotAStaleRead() throws {
        let credentials = InMemoryCredentialStore()
        let store = makeStore(credentials: credentials)

        try store.importCredential(keyFile: try Fixture.serviceAccountJSON())

        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.clientEmail, "perch@example.iam.gserviceaccount.com")
        // The import itself never called `load()`, and the `isConfigured`/
        // `clientEmail` reads above must not have gone back to the Keychain
        // either — `didLoadCredential` was already set by the import.
        XCTAssertEqual(credentials.loadCount, 0)
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

    /// Toggling the plugin off mid-fetch cancels the refresh task while
    /// `stats(for:today:)` is still in flight. Before the `Task.isCancelled`
    /// guard in `refresh()`, that in-flight call's cancellation error was
    /// mapped by the generic `catch` to `.malformedResponse` and recorded as
    /// a real failure — a spurious "Couldn't refresh" that could persist
    /// after re-enabling.
    func testCancellingMidRefreshRecordsNoFailure() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        api.setGate { try await Task.sleep(for: .seconds(5)) }
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])

        let task = Task { await store.refresh() }
        // Give the task group a real chance to reach the gate before
        // cancelling — bounded at 50ms, far more than a synchronous dispatch
        // needs.
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value

        XCTAssertTrue(store.failures.isEmpty)
        XCTAssertNil(store.credentialFailure)
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

    func testRenamingAPropertyKeepsItsIDAndStats() async throws {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats(users: 312))])
        let store = makeStore(credentials: try configuredCredentials(), api: api)
        store.setProperties([siteA])
        await store.refresh()

        store.renameProperty(id: "111", to: "prasanthsasikumar.com")

        XCTAssertEqual(store.properties.map(\.displayName), ["prasanthsasikumar.com"])
        XCTAssertEqual(store.properties.map(\.id), ["111"])
        // Renaming is not re-adding: the numbers already fetched stay put.
        XCTAssertEqual(store.stats["111"]?.currentWeek.activeUsers, 312)
    }

    /// The name field is a live binding, so it is empty for as long as it
    /// takes to clear it and type something else. A card must not go nameless
    /// in the meantime.
    func testAClearedNameFallsBackToThePropertyID() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        store.setProperties([siteA])

        store.renameProperty(id: "111", to: "")

        XCTAssertEqual(store.properties.first?.title, "111")
    }

    func testRenamingAnUnknownPropertyDoesNothing() {
        let store = makeStore(credentials: InMemoryCredentialStore())
        store.setProperties([siteA])
        store.renameProperty(id: "nope", to: "x")
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
