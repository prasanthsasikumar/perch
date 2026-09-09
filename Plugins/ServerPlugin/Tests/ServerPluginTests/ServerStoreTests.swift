@testable import ServerPlugin
import PerchKit
import XCTest

@MainActor
final class ServerStoreTests: XCTestCase {
    private var storage: PluginStorage!
    private var source: FakeSnapshotSource!
    private var credentials: InMemoryServerCredentials!
    private var clock: FakeClock!
    private var store: ServerStore!

    override func setUp() {
        super.setUp()
        storage = makeTemporaryStorage()
        source = FakeSnapshotSource()
        credentials = InMemoryServerCredentials()
        clock = FakeClock()
        store = makeStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storage.directory)
        super.tearDown()
    }

    private func makeStore() -> ServerStore {
        ServerStore(
            storage: storage,
            source: source,
            credentials: credentials,
            clock: { [clock] in clock!.now }
        )
    }

    // MARK: - Adding

    func testAddingNormalisesTheAddress() {
        let server = store.addServer(address: "status.example.com")
        XCTAssertEqual(server?.endpoint.absoluteString, "https://status.example.com/api/now")
    }

    func testAddingNamesTheServerAfterItsHostByDefault() {
        XCTAssertEqual(store.addServer(address: "https://status.example.com")?.name, "status.example.com")
    }

    func testAnExplicitNameWins() {
        XCTAssertEqual(
            store.addServer(address: "https://status.example.com", name: "Prod box")?.name,
            "Prod box"
        )
    }

    func testAddingRejectsAnUnusableAddress() {
        XCTAssertNil(store.addServer(address: "   "))
        XCTAssertTrue(store.servers.isEmpty)
    }

    /// The password must never reach the JSON document.
    func testThePasswordGoesToTheCredentialStoreNotTheDocument() throws {
        let server = store.addServer(address: "https://status.example.com", username: "me", password: "hunter2")!
        store.saveNow()

        XCTAssertEqual(credentials.password(for: server.id), "hunter2")

        let written = try String(contentsOf: storage.url(named: "servers.json"), encoding: .utf8)
        XCTAssertFalse(written.contains("hunter2"), "the password must not be written to disk")
    }

    func testDeletingAServerForgetsItsPassword() {
        let server = store.addServer(address: "https://a.example.com", username: "me", password: "hunter2")!
        store.deleteServer(id: server.id)
        XCTAssertNil(credentials.password(for: server.id))
        XCTAssertTrue(store.servers.isEmpty)
    }

    // MARK: - Refresh

    func testRefreshStoresASnapshotPerServer() async {
        let server = store.addServer(address: "https://a.example.com")!
        await store.refresh()
        XCTAssertEqual(store.snapshots[server.id]?.host, "test-host")
        XCTAssertNil(store.failures[server.id])
    }

    func testRefreshSendsTheStoredCredential() async {
        store.addServer(address: "https://a.example.com", username: "me", password: "hunter2")
        await store.refresh()
        XCTAssertEqual(source.requests.first?.username, "me")
        XCTAssertEqual(source.requests.first?.password, "hunter2")
    }

    func testAFailureBecomesAReadableMessage() async {
        let server = store.addServer(address: "https://a.example.com")!
        source.setOutcome(.failure(ServerError.unauthorized))
        await store.refresh()
        XCTAssertEqual(store.failures[server.id], "Wrong username or password.")
    }

    /// A dropped connection should not blank the card. The last known state is
    /// still the most useful thing on screen, dimmed.
    func testAFailureKeepsThePreviousSnapshot() async {
        let server = store.addServer(address: "https://a.example.com")!
        await store.refresh()
        source.setOutcome(.failure(ServerError.unreachable("a.example.com")))
        await store.refresh()

        XCTAssertNotNil(store.snapshots[server.id])
        XCTAssertNotNil(store.failures[server.id])
    }

    func testASuccessfulRefreshClearsAnEarlierFailure() async {
        let server = store.addServer(address: "https://a.example.com")!
        source.setOutcome(.failure(ServerError.unauthorized))
        await store.refresh()
        source.setOutcome(.success(makeSnapshot()))
        await store.refresh()
        XCTAssertNil(store.failures[server.id])
    }

    func testAnUnexpectedErrorTypeStillProducesACaption() async {
        struct Weird: Error {}
        let server = store.addServer(address: "https://a.example.com")!
        source.setOutcome(.failure(Weird()))
        await store.refresh()
        XCTAssertEqual(store.failures[server.id], "Something went wrong while checking.")
    }

    // MARK: - Staleness

    func testNeedsRefreshWhenAServerHasNeverBeenChecked() {
        store.addServer(address: "https://a.example.com")
        XCTAssertTrue(store.needsRefresh(maxAge: 60))
    }

    func testFreshNumbersAreLeftAlone() async {
        store.addServer(address: "https://a.example.com")
        await store.refresh()
        clock.advance(10)
        XCTAssertFalse(store.needsRefresh(maxAge: 60))
    }

    func testStaleNumbersAreRefetched() async {
        store.addServer(address: "https://a.example.com")
        await store.refresh()
        clock.advance(120)
        XCTAssertTrue(store.needsRefresh(maxAge: 60))
    }

    // MARK: - Trend

    func testEachRefreshAppendsATrendPoint() async {
        let server = store.addServer(address: "https://a.example.com")!
        await store.refresh()
        clock.advance(60)
        await store.refresh()
        XCTAssertEqual(store.trends[server.id]?.count, 2)
    }

    /// A snapshot with no CPU data would otherwise be recorded as zero and
    /// draw a trough that never happened.
    func testASnapshotWithoutCPUDataIsNotRecorded() async {
        let server = store.addServer(address: "https://a.example.com")!
        source.setOutcome(.success(makeSnapshot(ready: false, cpuIdle: nil)))
        await store.refresh()
        XCTAssertNil(store.trends[server.id])
    }

    func testTheTrendIsCappedAndKeepsTheNewestPoints() async {
        let server = store.addServer(address: "https://a.example.com")!
        for index in 0..<(ServerStore.trendCapacity + 10) {
            source.setOutcome(.success(makeSnapshot(cpuIdle: Double(index % 100))))
            clock.advance(60)
            await store.refresh()
        }
        let points = store.trends[server.id]
        XCTAssertEqual(points?.count, ServerStore.trendCapacity)
        // The last sample written was index 129, so idle 29, so busy 71.
        XCTAssertEqual(points?.last?.cpu ?? 0, 71, accuracy: 0.001)
    }

    // MARK: - Derived

    func testMenuBarShowsTheFirstServersCPU() async {
        store.addServer(address: "https://a.example.com")
        source.setOutcome(.success(makeSnapshot(cpuIdle: 75)))
        await store.refresh()
        XCTAssertEqual(store.menuBarCPU, 25)
    }

    /// A stale percentage looks identical to a live one, so a server that is
    /// failing must not keep feeding the menu bar.
    func testMenuBarGoesQuietWhenTheFirstServerIsFailing() async {
        store.addServer(address: "https://a.example.com")
        await store.refresh()
        source.setOutcome(.failure(ServerError.unreachable("a.example.com")))
        await store.refresh()
        XCTAssertNil(store.menuBarCPU)
        XCTAssertTrue(store.hasUnreachableServer)
    }

    func testWorstAlertLevelIsTheMaximumAcrossServers() async {
        store.addServer(address: "https://a.example.com")
        source.setOutcome(.success(makeSnapshot(zombies: 2)))
        await store.refresh()
        XCTAssertEqual(store.worstAlertLevel, .warning)

        source.setOutcome(.success(makeSnapshot(fsTotal: 100, fsUsed: 95)))
        await store.refresh()
        XCTAssertEqual(store.worstAlertLevel, .critical)
    }

    // MARK: - Persistence

    func testServersAndTrendsSurviveAReload() async {
        let server = store.addServer(address: "https://a.example.com", name: "Box")!
        await store.refresh()
        store.saveNow()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.servers.map(\.name), ["Box"])
        XCTAssertEqual(reloaded.snapshots[server.id]?.host, "test-host")
        XCTAssertEqual(reloaded.trends[server.id]?.count, 1)
    }

    func testSettingsSurviveAReload() {
        store.updateSettings(ServerSettings(refreshIntervalSeconds: 120))
        store.saveNow()
        XCTAssertEqual(makeStore().settings.refreshIntervalSeconds, 120)
    }

    func testAnUnreadableDocumentIsReportedRatherThanCrashing() throws {
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storage.url(named: "servers.json"))

        let reloaded = makeStore()
        XCTAssertNotNil(reloaded.loadFailureNotice)
        XCTAssertTrue(reloaded.servers.isEmpty)
    }
}

@MainActor
final class ServerCredentialFailureTests: XCTestCase {
    /// A Keychain that refuses the write must not leave the user with a server
    /// that silently has no password: every refresh would then report a wrong
    /// password, which is a lie about where the problem is.
    func testARefusedKeychainWriteIsReported() {
        let credentials = InMemoryServerCredentials()
        credentials.succeeds = false
        let store = ServerStore(
            storage: makeTemporaryStorage(),
            source: FakeSnapshotSource(),
            credentials: credentials
        )
        store.addServer(address: "https://a.example.com", username: "me", password: "hunter2")
        XCTAssertNotNil(store.credentialFailureNotice)
    }

    func testASuccessfulWriteLeavesNoNotice() {
        let store = ServerStore(
            storage: makeTemporaryStorage(),
            source: FakeSnapshotSource(),
            credentials: InMemoryServerCredentials()
        )
        store.addServer(address: "https://a.example.com", username: "me", password: "hunter2")
        XCTAssertNil(store.credentialFailureNotice)
    }

    /// Adding a server with no password at all is ordinary, not a failure.
    func testNoPasswordIsNotAFailure() {
        let credentials = InMemoryServerCredentials()
        credentials.succeeds = false
        let store = ServerStore(
            storage: makeTemporaryStorage(),
            source: FakeSnapshotSource(),
            credentials: credentials
        )
        store.addServer(address: "https://a.example.com")
        XCTAssertNil(store.credentialFailureNotice)
    }
}
