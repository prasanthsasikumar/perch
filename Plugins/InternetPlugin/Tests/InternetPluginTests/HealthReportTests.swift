@testable import InternetPlugin
import XCTest

final class HealthReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func evaluate(_ checks: [Check], path: PathStatus? = wifi) -> HealthReport {
        HealthReport.evaluate(checks: checks, path: path, targets: ProbeTarget.defaults, now: now)
    }

    /// `count` checks thirty seconds apart, ending now.
    private func series(_ count: Int, _ make: (Int, Date) -> Check) -> [Check] {
        (0..<count).map { index in
            make(index, now.addingTimeInterval(-30 * Double(count - 1 - index)))
        }
    }

    func testNoChecksIsStillChecking() {
        XCTAssertEqual(evaluate([]).verdict, .checking)
    }

    func testANetworkWithNoPathIsNoNetworkWhateverTheChecksSay() {
        let checks = series(3) { _, at in makeCheck(at: at) }
        XCTAssertEqual(evaluate(checks, path: PathStatus(isSatisfied: false, interface: nil)).verdict, .noNetwork)
    }

    func testFastAndCleanIsGood() {
        let report = evaluate(series(10) { _, at in makeCheck(at: at) })
        XCTAssertEqual(report.verdict, .good)
        XCTAssertEqual(report.latency, 20)
        XCTAssertEqual(report.jitter, 0)
        XCTAssertEqual(report.loss, 0)
    }

    func testLatencyIsTheFastestTargetPerCheck() {
        let check = makeCheck(at: now, overrides: [
            "cloudflare": .ok(milliseconds: 12),
            "google": .ok(milliseconds: 80),
        ])
        XCTAssertEqual(evaluate([check]).latency, 12)
    }

    func testEverythingFailingNowIsOfflineEvenAfterAGoodHistory() {
        var checks = series(9) { _, at in makeCheck(at: at.addingTimeInterval(-30)) }
        checks.append(makeCheck(at: now, .failed))
        XCTAssertEqual(evaluate(checks).verdict, .offline)
    }

    func testAnInterceptedAnswerIsACaptivePortal() {
        let check = makeCheck(at: now, .failed, overrides: ["apple": .intercepted])
        XCTAssertEqual(evaluate([check]).verdict, .captivePortal)
    }

    func testReachableByIPButNotByNameIsDNS() {
        let check = makeCheck(at: now, .dnsFailed, overrides: ["cloudflare": .ok(milliseconds: 15)])
        XCTAssertEqual(evaluate([check]).verdict, .dnsBroken)
    }

    func testHighLossIsPoor() {
        // One target in three failing on every check: a third lost.
        let checks = series(10) { _, at in makeCheck(at: at, overrides: ["google": .failed]) }
        XCTAssertEqual(evaluate(checks).verdict, .poor)
    }

    func testASingleDroppedProbeDoesNotSpoilTheVerdict() {
        let checks = series(10) { index, at in
            makeCheck(at: at, overrides: index == 4 ? ["google": .failed] : [:])
        }
        XCTAssertEqual(evaluate(checks).verdict, .good)
    }

    func testAFewDroppedProbesIsFair() {
        let checks = series(10) { index, at in
            makeCheck(at: at, overrides: index.isMultiple(of: 5) ? ["google": .failed] : [:])
        }
        XCTAssertEqual(evaluate(checks).verdict, .fair)
    }

    func testSlowIsFairThenPoor() {
        XCTAssertEqual(evaluate(series(5) { _, at in makeCheck(at: at, .ok(milliseconds: 180)) }).verdict, .fair)
        XCTAssertEqual(evaluate(series(5) { _, at in makeCheck(at: at, .ok(milliseconds: 450)) }).verdict, .poor)
    }

    func testJumpyLatencyIsFair() {
        let checks = series(10) { index, at in
            makeCheck(at: at, .ok(milliseconds: index.isMultiple(of: 2) ? 10 : 100))
        }
        XCTAssertEqual(evaluate(checks).verdict, .fair)
    }

    /// After a sleep, an hour-old failure must not be what the panel shows.
    func testOldChecksAreIgnored() {
        let stale = makeCheck(at: now.addingTimeInterval(-HealthReport.maxAge - 1), .failed)
        XCTAssertEqual(evaluate([stale]).verdict, .checking)
    }

    func testOnlyTheWindowCounts() {
        // Failures long enough ago to fall outside the last ten checks.
        let checks = series(20) { index, at in makeCheck(at: at, index < 10 ? .failed : .ok(milliseconds: 20)) }
        XCTAssertEqual(evaluate(checks).loss, 0)
    }

    func testMedianAndStep() {
        XCTAssertNil(HealthReport.median([]))
        XCTAssertEqual(HealthReport.median([3, 1, 2]), 2)
        XCTAssertEqual(HealthReport.median([4, 1, 2, 3]), 2.5)
        XCTAssertNil(HealthReport.meanStep([5]))
        XCTAssertEqual(HealthReport.meanStep([10, 20, 10]), 10)
    }
}
