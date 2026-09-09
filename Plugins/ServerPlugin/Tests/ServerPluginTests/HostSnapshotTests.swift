@testable import ServerPlugin
import XCTest

final class HostSnapshotTests: XCTestCase {
    private func decode(_ json: String) throws -> HostSnapshot {
        try HTTPSnapshotSource.decoder.decode(HostSnapshot.self, from: Data(json.utf8))
    }

    /// The shape the agent actually serves, snake_case and all.
    func testDecodesTheAgentPayload() throws {
        let snapshot = try decode(#"""
        {
          "host": "dedirock", "ts": 1788939210.5, "uptime": 4893000.0, "ncpu": 1, "ready": true,
          "cpu_user": 61.07, "cpu_sys": 24.67, "cpu_idle": 14.16, "cpu_iowait": 0.0, "cpu_steal": 0.1,
          "load1": 6.42, "load5": 6.33, "load15": 5.66,
          "procs": 650, "procs_running": 1, "procs_blocked": 0, "zombies": 16,
          "mem_total": 2063765504, "mem_used": 1198587904, "mem_avail": 865177600, "mem_cache": 799113216,
          "swap_total": 4294959104, "swap_used": 1428930560, "swap_in": 9829.78, "swap_out": 0.0,
          "fs_total": 29958533120, "fs_used": 24580227072,
          "disk_read_bps": 51606.35, "disk_write_bps": 138436.08,
          "net_rx_bps": 874.74, "net_tx_bps": 421.97,
          "traffic": {"today": {"rx": 52951, "tx": 33761},
                      "month": {"rx": 52951, "tx": 33761}, "since": "2026-09-09"},
          "containers": [{"name": "coolify", "status": "Up 4 days", "cpu": 26.0, "mem": 152043520}],
          "top_cpu": [{"pid": 271058, "name": "caddy", "cpu": 5.1, "rss": 34603008}],
          "top_mem": [{"pid": 2765199, "name": "next-server", "cpu": 0.2, "rss": 136314880}],
          "health": [{"name": "supabase", "url": "https://db/", "code": 401, "ok": true, "ms": 374, "error": null}],
          "units": [{"name": "caddy", "state": "active", "ok": true}]
        }
        """#)

        XCTAssertEqual(snapshot.host, "dedirock")
        XCTAssertEqual(snapshot.ncpu, 1)
        XCTAssertEqual(snapshot.zombies, 16)
        XCTAssertEqual(snapshot.load1, 6.42, accuracy: 0.001)
        XCTAssertEqual(snapshot.containers.first?.name, "coolify")
        XCTAssertEqual(snapshot.topCpu.first?.name, "caddy")
        XCTAssertEqual(snapshot.health.first?.code, 401)
        XCTAssertEqual(snapshot.traffic?.since, "2026-09-09")
    }

    /// The agent's first sample after a restart has no predecessor to
    /// difference against, so every rate key is simply absent. Requiring them
    /// would make Perch fail for the first minute of every agent restart.
    func testDecodesASnapshotWithNoRateFields() throws {
        let snapshot = try decode(#"""
        {
          "host": "fresh", "ts": 1788939210.0, "uptime": 60.0, "ncpu": 2, "ready": false,
          "load1": 0.1, "load5": 0.1, "load15": 0.1,
          "procs": 90, "procs_running": 1, "procs_blocked": 0, "zombies": 0,
          "mem_total": 100, "mem_used": 10, "mem_avail": 90, "mem_cache": 0,
          "swap_total": 0, "swap_used": 0,
          "fs_total": 100, "fs_used": 10,
          "containers": [], "top_cpu": [], "top_mem": [], "health": [], "units": []
        }
        """#)

        XCTAssertFalse(snapshot.ready)
        XCTAssertNil(snapshot.cpuIdle)
        XCTAssertNil(snapshot.cpuBusy)
        XCTAssertNil(snapshot.netRxBps)
        XCTAssertFalse(snapshot.isSwapping)
        XCTAssertEqual(snapshot.networkTotalBps, 0)
    }

    func testCPUBusyIsTheComplementOfIdle() {
        XCTAssertEqual(makeSnapshot(cpuIdle: 14.16).cpuBusy!, 85.84, accuracy: 0.001)
    }

    func testCPUBusyIsClampedIntoRange() {
        XCTAssertEqual(makeSnapshot(cpuIdle: -5).cpuBusy, 100)
        XCTAssertEqual(makeSnapshot(cpuIdle: 105).cpuBusy, 0)
    }

    /// A box with swap switched off divides by zero otherwise, and NaN would
    /// propagate into a bar width.
    func testFractionsAreZeroWhenTheTotalIsZero() {
        let snapshot = makeSnapshot(swapTotal: 0, swapUsed: 0)
        XCTAssertEqual(snapshot.swapFraction, 0)
        XCTAssertFalse(snapshot.swapFraction.isNaN)
    }

    func testLoadFractionIsRelativeToCores() {
        XCTAssertEqual(makeSnapshot(ncpu: 4, load1: 2.0).loadFraction, 0.5)
    }
}
