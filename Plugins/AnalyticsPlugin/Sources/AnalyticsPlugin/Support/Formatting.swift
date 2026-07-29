import Foundation

/// Number presentation, kept deliberately close to the Python summary this
/// plugin replaces so the same traffic reads as the same numbers.
public enum Formatting {
    /// `1234 -> "1.2K"`, `1500000 -> "1.5M"`, anything smaller grouped with
    /// separators. Fractions below a thousand are truncated, not rounded,
    /// matching `int(n)` in the script.
    public static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return grouped.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
    }

    /// Seconds as `m:ss`. GA reports average session duration in seconds with
    /// a long fractional tail that means nothing to a reader.
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// GA reports rates as a fraction; users read them as a percentage.
    public static func rate(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        return String(format: "%.1f%%", fraction * 100)
    }

    private static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

/// The change between two periods.
///
/// A type rather than a preformatted string, because the panel colours the
/// number by direction and a string would have to be parsed back to do that.
/// The two degenerate cases are the ones the Python script special-cases: a
/// zero baseline is either "nothing happened either week" or "everything is
/// new", and calling both of them "+∞%" would be a lie about the first.
public enum PercentChange: Equatable, Sendable {
    case change(Double)
    /// Both periods were zero. There is no change to report.
    case undefined
    /// The baseline was zero and this period was not.
    case fromZero

    public init(current: Double, previous: Double) {
        guard previous != 0 else {
            self = current == 0 ? .undefined : .fromZero
            return
        }
        self = .change((current - previous) / previous * 100)
    }

    public var text: String {
        switch self {
        case .change(let percent):
            String(format: "%@%.1f%%", percent > 0 ? "+" : "", percent)
        case .undefined:
            "N/A"
        case .fromZero:
            "new"
        }
    }

    /// `true` up, `false` down, `nil` for flat or undefined — which is exactly
    /// the three-way split the panel needs to pick a colour and an arrow.
    public var isUp: Bool? {
        switch self {
        case .change(let percent):
            percent == 0 ? nil : percent > 0
        case .fromZero:
            true
        case .undefined:
            nil
        }
    }
}
