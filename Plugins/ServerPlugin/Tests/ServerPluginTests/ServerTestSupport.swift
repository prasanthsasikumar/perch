@testable import ServerPlugin
import Foundation
import PerchKit

/// A snapshot with everything healthy. Tests change the one field they are
/// about, so a failure names the threshold that broke rather than drowning in
/// setup.
func makeSnapshot(
    host: String = "test-host",
    ncpu: Int = 2,
    ready: Bool = true,
    cpuIdle: Double? = 90,
    cpuSteal: Double? = 0,
    load1: Double = 0.2,
    zombies: Int = 0,
    memTotal: Double = 2_000_000_000,
    memUsed: Double = 500_000_000,
    swapTotal: Double = 1_000_000_000,
    swapUsed: Double = 0,
    swapIn: Double? = 0,
    swapOut: Double? = 0,
    fsTotal: Double = 30_000_000_000,
    fsUsed: Double = 10_000_000_000,
    health: [HostSnapshot.HealthCheck] = [],
    units: [HostSnapshot.Unit] = []
) -> HostSnapshot {
    HostSnapshot(
        host: host,
        ts: 1_700_000_000,
        uptime: 86_400,
        ncpu: ncpu,
        ready: ready,
        cpuUser: 5,
        cpuSys: 5,
        cpuIdle: cpuIdle,
        cpuIowait: 0,
        cpuSteal: cpuSteal,
        load1: load1,
        load5: load1,
        load15: load1,
        procs: 100,
        procsRunning: 1,
        procsBlocked: 0,
        zombies: zombies,
        memTotal: memTotal,
        memUsed: memUsed,
        memAvail: memTotal - memUsed,
        memCache: 0,
        swapTotal: swapTotal,
        swapUsed: swapUsed,
        swapIn: swapIn,
        swapOut: swapOut,
        fsTotal: fsTotal,
        fsUsed: fsUsed,
        diskReadBps: 0,
        diskWriteBps: 0,
        netRxBps: 1000,
        netTxBps: 500,
        traffic: nil,
        containers: [],
        topCpu: [],
        topMem: [],
        health: health,
        units: units
    )
}

/// A source the tests drive: it hands back whatever was queued, and records
/// what it was asked for so auth wiring can be asserted.
final class FakeSnapshotSource: SnapshotSource, @unchecked Sendable {
    enum Outcome {
        case success(HostSnapshot)
        case failure(Error)
    }

    private let lock = NSLock()
    private var _outcome: Outcome
    private var _requests: [SnapshotRequest] = []

    init(outcome: Outcome = .success(makeSnapshot())) {
        _outcome = outcome
    }

    var requests: [SnapshotRequest] { lock.withLock { _requests } }

    func setOutcome(_ outcome: Outcome) {
        lock.withLock { _outcome = outcome }
    }

    func fetch(_ request: SnapshotRequest) async throws -> HostSnapshot {
        let outcome: Outcome = lock.withLock {
            _requests.append(request)
            return _outcome
        }
        switch outcome {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        _now = start
    }

    var now: Date { lock.withLock { _now } }

    func advance(_ interval: TimeInterval) {
        lock.withLock { _now += interval }
    }
}

/// A storage rooted in a fresh temporary directory, so tests never touch the
/// developer's real Application Support.
func makeTemporaryStorage() -> PluginStorage {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ServerPluginTests-\(UUID().uuidString)", isDirectory: true)
    return PluginStorage(directory: directory)
}
