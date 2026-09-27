@testable import InternetPlugin
import PerchKit
import XCTest

@MainActor
final class InternetStoreTests: XCTestCase {
    private var storage: PluginStorage!
    private var source: FakeProbeSource!
    private var speedTester: FakeSpeedTester!
    private var clock: FakeClock!
    private var store: InternetStore!

    override func setUp() {
        super.setUp()
        storage = makeTemporaryStorage()
        source = FakeProbeSource()
        speedTester = FakeSpeedTester()
        clock = FakeClock()
        store = makeStore()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storage.directory)
        super.tearDown()
    }

    private func makeStore() -> InternetStore {
        InternetStore(
            storage: storage,
            source: source,
            speedTester: speedTester,
            clock: { [clock] in clock!.now }
        )
    }

    func testACheckAsksEveryTarget() async {
        await store.check()
        XCTAssertEqual(source.calls, ProbeTarget.defaults.count)
        XCTAssertEqual(store.checks.count, 1)
        XCTAssertEqual(Set(store.latestOutcomes.keys), Set(ProbeTarget.defaults.map(\.id)))
    }

    func testHistoryIsCapped() async {
        for _ in 0..<(InternetStore.checkCapacity + 5) {
            clock.advance(30)
            await store.check()
        }
        XCTAssertEqual(store.checks.count, InternetStore.checkCapacity)
        XCTAssertEqual(store.checks.last?.at, clock.now)
    }

    func testCheckIfStaleSkipsAFreshCheck() async {
        await store.check()
        clock.advance(10)
        await store.checkIfStale(maxAge: 15)
        XCTAssertEqual(store.checks.count, 1)
        clock.advance(10)
        await store.checkIfStale(maxAge: 15)
        XCTAssertEqual(store.checks.count, 2)
    }

    func testChecksAndSpeedSurviveARelaunch() async {
        await store.check()
        await store.testSpeed()
        store.saveNow()

        let reopened = makeStore()
        XCTAssertEqual(reopened.checks, store.checks)
        XCTAssertEqual(reopened.speed?.megabitsPerSecond, 100)
    }

    func testAFailedSpeedTestKeepsTheLastResult() async {
        await store.testSpeed()
        speedTester.result = .failure(URLError(.timedOut))
        await store.testSpeed()
        XCTAssertEqual(store.speed?.megabitsPerSecond, 100)
        XCTAssertNotNil(store.speedFailure)
        XCTAssertFalse(store.isTestingSpeed)
    }

    /// The first path report is just macOS saying where things stand; the
    /// loop is about to check anyway.
    func testTheFirstPathReportDoesNotCheck() async {
        await store.pathChanged(wifi)
        XCTAssertEqual(store.checks.count, 0)
    }

    func testChangingNetworkChecksStraightAway() async {
        await store.pathChanged(wifi)
        await store.pathChanged(PathStatus(isSatisfied: true, interface: .ethernet))
        XCTAssertEqual(store.checks.count, 1)
    }

    func testLosingTheNetworkDoesNotBotherChecking() async {
        await store.pathChanged(wifi)
        await store.pathChanged(PathStatus(isSatisfied: false, interface: nil))
        XCTAssertEqual(store.checks.count, 0)
        XCTAssertEqual(store.report.verdict, .noNetwork)
    }

    func testReportUsesTheStoresClock() async {
        source.setAll(.failed)
        await store.check()
        XCTAssertEqual(store.report.verdict, .offline)
        clock.advance(HealthReport.maxAge + 1)
        XCTAssertEqual(store.report.verdict, .checking)
    }
}
