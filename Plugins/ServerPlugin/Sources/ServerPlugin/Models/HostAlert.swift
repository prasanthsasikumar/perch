import Foundation

/// Something about a host worth putting in front of the user.
public struct HostAlert: Identifiable, Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case warning
        case critical

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: String
    public let level: Level
    public let message: String

    public init(id: String, level: Level, message: String) {
        self.id = id
        self.level = level
        self.message = message
    }
}

/// The thresholds, in one place.
///
/// Pure and separate from the views on purpose: "when is a box in trouble" is
/// the part of this plugin most worth testing, and it should not need a
/// SwiftUI environment to exercise.
public enum HostAlerts {
    /// Root filesystem, as a fraction.
    public static let diskWarning = 0.80
    public static let diskCritical = 0.90
    /// Multiples of the core count.
    public static let loadWarning = 1.0
    public static let loadCritical = 2.0
    /// Percent of a vCPU taken by the hypervisor for someone else.
    public static let stealWarning = 5.0
    /// Fraction of swap in use that is worth mentioning even when nothing is
    /// actively paging.
    public static let swapWarning = 0.25

    public static func evaluate(_ snapshot: HostSnapshot) -> [HostAlert] {
        var alerts: [HostAlert] = []

        let disk = snapshot.diskFraction
        if disk >= diskCritical {
            alerts.append(HostAlert(
                id: "disk", level: .critical,
                message: "Disk \(percent(disk)) full, \(Format.bytes(snapshot.fsTotal - snapshot.fsUsed)) left"))
        } else if disk >= diskWarning {
            alerts.append(HostAlert(
                id: "disk", level: .warning,
                message: "Disk \(percent(disk)) full, \(Format.bytes(snapshot.fsTotal - snapshot.fsUsed)) left"))
        }

        let cores = Double(max(snapshot.ncpu, 1))
        if snapshot.load1 >= cores * loadCritical {
            alerts.append(HostAlert(
                id: "load", level: .critical,
                message: "Load \(Format.load(snapshot.load1)) on \(snapshot.ncpu) core\(snapshot.ncpu == 1 ? "" : "s"), processes are queuing"))
        } else if snapshot.load1 >= cores * loadWarning {
            alerts.append(HostAlert(
                id: "load", level: .warning,
                message: "Load \(Format.load(snapshot.load1)) is at or above \(snapshot.ncpu) core\(snapshot.ncpu == 1 ? "" : "s")"))
        }

        // Actively paging is the real signal. Swap merely occupied is worth a
        // quieter mention: it may be pages parked there long ago that nothing
        // has needed since.
        if snapshot.isSwapping {
            alerts.append(HostAlert(
                id: "swap", level: .warning,
                message: "Swapping now, in \(Format.rate(snapshot.swapIn ?? 0)) out \(Format.rate(snapshot.swapOut ?? 0))"))
        } else if snapshot.swapFraction > swapWarning {
            alerts.append(HostAlert(
                id: "swap", level: .warning,
                message: "\(Format.bytes(snapshot.swapUsed)) sitting in swap"))
        }

        if let steal = snapshot.cpuSteal, steal > stealWarning {
            alerts.append(HostAlert(
                id: "steal", level: .warning,
                message: "CPU steal \(Format.percent(steal)), the host is busy elsewhere"))
        }

        if snapshot.zombies > 0 {
            alerts.append(HostAlert(
                id: "zombies", level: .warning,
                message: "\(snapshot.zombies) zombie process\(snapshot.zombies == 1 ? "" : "es")"))
        }

        let down = snapshot.health.filter { !$0.ok }.map(\.name)
        if !down.isEmpty {
            alerts.append(HostAlert(
                id: "health", level: .critical,
                message: "Unreachable: \(down.joined(separator: ", "))"))
        }

        let dead = snapshot.units.filter { !$0.ok }.map(\.name)
        if !dead.isEmpty {
            alerts.append(HostAlert(
                id: "units", level: .critical,
                message: "Not running: \(dead.joined(separator: ", "))"))
        }

        // Critical first, but otherwise the order above, which runs roughly
        // from "will break the box" to "worth a look".
        return alerts.sorted { $0.level > $1.level }
    }

    private static func percent(_ fraction: Double) -> String {
        Format.percent(fraction * 100)
    }
}
