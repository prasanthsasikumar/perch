import Foundation

/// What macOS says about the link itself, before anything is asked of the
/// internet.
public struct PathStatus: Equatable, Sendable {
    public enum Interface: String, Sendable {
        case wifi = "Wi-Fi"
        case ethernet = "Ethernet"
        case cellular = "Cellular"
        case other = "Network"
    }

    public var isSatisfied: Bool
    public var interface: Interface?
    /// A hotspot or a metered link. Worth saying before someone runs a speed
    /// test on their phone's data plan.
    public var isExpensive: Bool
    /// Low Data Mode.
    public var isConstrained: Bool

    public init(isSatisfied: Bool, interface: Interface?, isExpensive: Bool = false, isConstrained: Bool = false) {
        self.isSatisfied = isSatisfied
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

/// The verdict the panel leads with and the menu bar icon reflects.
public struct HealthReport: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case checking
        case offline
        case noNetwork
        case captivePortal
        case dnsBroken
        case poor
        case fair
        case good

        public var title: String {
            switch self {
            case .checking: "Checking…"
            case .offline: "Offline"
            case .noNetwork: "No network"
            case .captivePortal: "Sign-in needed"
            case .dnsBroken: "DNS isn't working"
            case .poor: "Poor"
            case .fair: "Fair"
            case .good: "Healthy"
            }
        }
    }

    public var verdict: Verdict
    /// One sentence under the title saying why.
    public var reason: String
    /// Median of each check's fastest answer, in milliseconds.
    public var latency: Double?
    /// Mean change in latency from one check to the next, in milliseconds.
    public var jitter: Double?
    /// Share of probes that got no proper answer, 0...1.
    public var loss: Double?

    /// How many recent checks the numbers are taken over. At the 30-second
    /// interval, five minutes: long enough that one dropped probe does not
    /// flip the verdict, short enough to recover soon after a problem ends.
    public static let window = 10
    /// Checks older than this say nothing about now — after a sleep, say.
    public static let maxAge: TimeInterval = 10 * 60

    public static let poorLatency: Double = 300
    public static let fairLatency: Double = 120
    public static let fairJitter: Double = 40
    public static let poorLoss: Double = 0.2
    public static let fairLoss: Double = 0.05

    public static func evaluate(
        checks: [Check],
        path: PathStatus?,
        targets: [ProbeTarget],
        now: Date
    ) -> HealthReport {
        if let path, !path.isSatisfied {
            return HealthReport(verdict: .noNetwork, reason: "Not connected to any network.")
        }

        let recent = Array(checks.filter { now.timeIntervalSince($0.at) <= maxAge }.suffix(window))
        guard let latest = recent.last else {
            return HealthReport(verdict: .checking, reason: "Waiting for the first check.")
        }

        let latencies = recent.compactMap(\.latency)
        let probes = recent.reduce(0) { $0 + $1.outcomes.count }
        let failed = recent.reduce(0) { $0 + $1.failures }
        let loss = probes > 0 ? Double(failed) / Double(probes) : nil
        let latency = median(latencies)
        let jitter = meanStep(latencies)

        func report(_ verdict: Verdict, _ reason: String) -> HealthReport {
            HealthReport(verdict: verdict, reason: reason, latency: latency, jitter: jitter, loss: loss)
        }

        // The latest check decides the hard failures: someone looking at this
        // wants to know about now, not an average that includes it working.
        if latest.outcomes.values.contains(.intercepted) {
            return report(.captivePortal, "Something is answering in the internet's place — usually a Wi-Fi login page.")
        }
        let direct = targets.filter { !$0.usesDNS }.map(\.id)
        let named = targets.filter(\.usesDNS).map(\.id)
        let directOK = direct.contains { latest.outcomes[$0]?.isOK == true }
        let namesFailedDNS = !named.isEmpty && named.allSatisfy { latest.outcomes[$0] == .dnsFailed }
        if directOK && namesFailedDNS {
            return report(.dnsBroken, "The internet is reachable, but names aren't resolving.")
        }
        if latest.allFailed {
            return report(.offline, "Connected to a network, but nothing on the internet is answering.")
        }

        let lost = loss ?? 0
        let ms = latency ?? 0
        let jit = jitter ?? 0
        if lost >= poorLoss {
            return report(.poor, "\(Format.percent(lost)) of checks are going unanswered.")
        }
        if ms > poorLatency {
            return report(.poor, "Responses are very slow.")
        }
        if lost >= fairLoss {
            return report(.fair, "Some checks are going unanswered.")
        }
        if ms > fairLatency {
            return report(.fair, "Responses are slower than usual.")
        }
        if jit > fairJitter {
            return report(.fair, "Response times are jumping around.")
        }
        return report(.good, "Everything is answering quickly.")
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func meanStep(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return nil }
        let steps = zip(values, values.dropFirst()).map { abs($1 - $0) }
        return steps.reduce(0, +) / Double(steps.count)
    }
}
