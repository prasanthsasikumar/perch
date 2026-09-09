import Foundation

/// Small formatters shared by the panel and the alert messages.
///
/// Hand-rolled rather than `ByteCountFormatter` because this needs binary
/// units (the agent reports KiB-based figures, matching `free` and `df`) and
/// a stable one-or-zero decimal, which the system formatter will not give.
public enum Format {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func bytes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0 B" }
        var amount = value
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        // One decimal only where it carries information: "1.4 GB" is useful,
        // "938.0 MB" is noise.
        let decimals = (amount < 10 && index > 0) ? 1 : 0
        return String(format: "%.\(decimals)f %@", amount, units[index])
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    public static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value.isFinite ? value : 0)
    }

    public static func load(_ value: Double) -> String {
        String(format: "%.2f", value.isFinite ? value : 0)
    }

    /// "6d 4h", "4h 12m", "12m" — the two largest units that are non-zero,
    /// which is as much as a menu bar panel has room for.
    public static func uptime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "unknown" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
