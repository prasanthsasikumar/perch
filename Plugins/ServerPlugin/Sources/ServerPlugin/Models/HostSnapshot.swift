import Foundation

/// One reading from a vpsstat agent's `/api/now`.
///
/// Every rate field is optional because the agent's first sample after a
/// restart has no predecessor to difference against, and a percentage needs
/// two samples to exist. That snapshot arrives with `ready: false` and the
/// rate keys simply absent, so decoding must not require them.
public struct HostSnapshot: Codable, Equatable, Sendable {
    public struct Container: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var status: String
        public var cpu: Double
        public var mem: Double

        public var id: String { name }
    }

    public struct Process: Codable, Equatable, Sendable, Identifiable {
        public var pid: Int
        public var name: String
        public var cpu: Double
        public var rss: Double

        public var id: Int { pid }
    }

    public struct HealthCheck: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var ok: Bool
        public var code: Int?
        public var ms: Int?
        public var error: String?

        public var id: String { name }
    }

    public struct Unit: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var state: String
        public var ok: Bool

        public var id: String { name }
    }

    public struct TrafficWindow: Codable, Equatable, Sendable {
        public var rx: Double
        public var tx: Double
    }

    public struct Traffic: Codable, Equatable, Sendable {
        public var today: TrafficWindow
        public var month: TrafficWindow
        /// The day the agent started counting. Its totals are its own deltas,
        /// so they do not run from boot and the panel says so.
        public var since: String?
    }

    public var host: String
    public var ts: Double
    public var uptime: Double
    public var ncpu: Int
    public var ready: Bool

    public var cpuUser: Double?
    public var cpuSys: Double?
    public var cpuIdle: Double?
    public var cpuIowait: Double?
    public var cpuSteal: Double?

    public var load1: Double
    public var load5: Double
    public var load15: Double
    public var procs: Int
    public var procsRunning: Int
    public var procsBlocked: Int
    public var zombies: Int

    public var memTotal: Double
    public var memUsed: Double
    public var memAvail: Double
    public var memCache: Double
    public var swapTotal: Double
    public var swapUsed: Double
    public var swapIn: Double?
    public var swapOut: Double?

    public var fsTotal: Double
    public var fsUsed: Double
    public var diskReadBps: Double?
    public var diskWriteBps: Double?

    public var netRxBps: Double?
    public var netTxBps: Double?
    public var traffic: Traffic?

    public var containers: [Container]
    public var topCpu: [Process]
    public var topMem: [Process]
    public var health: [HealthCheck]
    public var units: [Unit]

    // MARK: - Derived

    /// How much of the CPU is not idle. Derived from idle rather than summed
    /// from the parts, because the parts here are only the ones worth showing
    /// and would under-count.
    public var cpuBusy: Double? {
        cpuIdle.map { max(0, min(100, 100 - $0)) }
    }

    public var memoryFraction: Double { fraction(memUsed, of: memTotal) }
    public var swapFraction: Double { fraction(swapUsed, of: swapTotal) }
    public var diskFraction: Double { fraction(fsUsed, of: fsTotal) }

    /// Load relative to the core count, which is the only way a load average
    /// means anything: 4.0 is idle on 8 cores and dire on 1.
    public var loadFraction: Double { fraction(load1, of: Double(ncpu)) }

    public var isSwapping: Bool { (swapIn ?? 0) + (swapOut ?? 0) > 0 }

    public var networkTotalBps: Double { (netRxBps ?? 0) + (netTxBps ?? 0) }

    private func fraction(_ part: Double, of whole: Double) -> Double {
        whole > 0 ? part / whole : 0
    }
}
