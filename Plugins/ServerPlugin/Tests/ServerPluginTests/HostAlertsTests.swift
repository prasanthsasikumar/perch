@testable import ServerPlugin
import XCTest

final class HostAlertsTests: XCTestCase {
    private func ids(_ snapshot: HostSnapshot) -> [String] {
        HostAlerts.evaluate(snapshot).map(\.id)
    }

    func testAHealthyHostRaisesNothing() {
        XCTAssertTrue(HostAlerts.evaluate(makeSnapshot()).isEmpty)
    }

    // MARK: - Disk

    func testDiskWarnsAtEightyPercent() {
        let snapshot = makeSnapshot(fsTotal: 100, fsUsed: 80)
        XCTAssertEqual(HostAlerts.evaluate(snapshot).first?.level, .warning)
    }

    func testDiskIsCriticalAtNinetyPercent() {
        let snapshot = makeSnapshot(fsTotal: 100, fsUsed: 90)
        XCTAssertEqual(HostAlerts.evaluate(snapshot).first?.level, .critical)
    }

    func testDiskIsQuietJustUnderTheThreshold() {
        XCTAssertFalse(ids(makeSnapshot(fsTotal: 100, fsUsed: 79)).contains("disk"))
    }

    // MARK: - Load

    /// The whole point of the core count: 4.0 is dire on one core and fine on
    /// eight, and a threshold that ignored that would cry wolf on every big box.
    func testLoadIsJudgedAgainstTheCoreCount() {
        XCTAssertTrue(ids(makeSnapshot(ncpu: 1, load1: 1.2)).contains("load"))
        XCTAssertFalse(ids(makeSnapshot(ncpu: 8, load1: 1.2)).contains("load"))
    }

    func testLoadIsCriticalAtTwiceTheCoreCount() {
        let alerts = HostAlerts.evaluate(makeSnapshot(ncpu: 2, load1: 4.0))
        XCTAssertEqual(alerts.first(where: { $0.id == "load" })?.level, .critical)
    }

    // MARK: - Swap

    func testActivePagingIsReportedEvenWhenSwapUsageIsSmall() {
        let snapshot = makeSnapshot(swapUsed: 1_000, swapIn: 4_096, swapOut: 0)
        XCTAssertTrue(ids(snapshot).contains("swap"))
    }

    func testOccupiedSwapAloneIsReportedOnlyPastTheThreshold() {
        XCTAssertFalse(ids(makeSnapshot(swapTotal: 100, swapUsed: 10)).contains("swap"))
        XCTAssertTrue(ids(makeSnapshot(swapTotal: 100, swapUsed: 30)).contains("swap"))
    }

    func testNotPagingAndEmptySwapIsQuiet() {
        XCTAssertFalse(ids(makeSnapshot(swapUsed: 0, swapIn: 0, swapOut: 0)).contains("swap"))
    }

    // MARK: - Other signals

    func testStealIsReportedPastFivePercent() {
        XCTAssertTrue(ids(makeSnapshot(cpuSteal: 6)).contains("steal"))
        XCTAssertFalse(ids(makeSnapshot(cpuSteal: 4)).contains("steal"))
    }

    func testZombiesAreReported() {
        XCTAssertTrue(ids(makeSnapshot(zombies: 1)).contains("zombies"))
    }

    func testZombieMessageIsSingularForOne() {
        let alert = HostAlerts.evaluate(makeSnapshot(zombies: 1)).first { $0.id == "zombies" }
        XCTAssertEqual(alert?.message, "1 zombie process")
    }

    func testFailedHealthChecksAreCritical() {
        let snapshot = makeSnapshot(health: [
            .init(name: "api", ok: false, code: nil, ms: nil, error: "timeout"),
            .init(name: "web", ok: true, code: 200, ms: 40, error: nil),
        ])
        let alert = HostAlerts.evaluate(snapshot).first { $0.id == "health" }
        XCTAssertEqual(alert?.level, .critical)
        XCTAssertEqual(alert?.message, "Unreachable: api")
    }

    func testStoppedUnitsAreCritical() {
        let snapshot = makeSnapshot(units: [.init(name: "caddy", state: "failed", ok: false)])
        XCTAssertEqual(HostAlerts.evaluate(snapshot).first { $0.id == "units" }?.level, .critical)
    }

    // MARK: - Ordering

    func testCriticalAlertsSortAboveWarnings() {
        let snapshot = makeSnapshot(
            zombies: 3,
            fsTotal: 100, fsUsed: 95,
            units: [.init(name: "docker", state: "inactive", ok: false)]
        )
        let levels = HostAlerts.evaluate(snapshot).map(\.level)
        XCTAssertEqual(levels, levels.sorted(by: >), "criticals must come first")
        XCTAssertEqual(levels.first, .critical)
    }

    /// The agent's first sample after a restart carries no rate fields at all.
    /// Evaluating it must not crash and must not invent problems.
    func testASnapshotWithNoRateDataRaisesNothingSpurious() {
        let snapshot = makeSnapshot(ready: false, cpuIdle: nil, cpuSteal: nil, swapIn: nil, swapOut: nil)
        XCTAssertTrue(HostAlerts.evaluate(snapshot).isEmpty)
    }
}
