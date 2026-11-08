import CoreGraphics

// The approach here follows Scroll Reverser by Nick Moore
// (github.com/pilotmoon/Scroll-Reverser, Apache 2.0): negate the line,
// fixed-point and point deltas of each scroll event in place, line delta
// first. No code is copied; the order of writes is the part learned from it.

/// Where a scroll came from, as far as a scroll event can tell.
public enum ScrollDevice: String, Codable, Sendable {
    case mouse
    case trackpad

    public var displayName: String {
        switch self {
        case .mouse: "Mouse"
        case .trackpad: "Trackpad"
        }
    }
}

public enum ScrollClassifier {
    /// A trackpad scroll always carries a phase: a gesture phase while the
    /// fingers are down (may-begin, began, changed, ended) and a momentum
    /// phase while it coasts afterwards. A wheel click carries neither.
    ///
    /// A Magic Mouse reports phases too, since its surface is a small
    /// trackpad, so it counts as a trackpad here. So does anything that
    /// emulates one. A mouse whose driver smooths the wheel into continuous
    /// scrolling without phases still counts as a mouse, which is what its
    /// owner expects.
    ///
    /// Scroll Reverser identifies the sending HID device through private
    /// SPI; the phases need none and are enough to separate the two.
    public static func device(scrollPhase: Int64, momentumPhase: Int64) -> ScrollDevice {
        scrollPhase != 0 || momentumPhase != 0 ? .trackpad : .mouse
    }
}

/// Which directions to reverse.
public struct ScrollAxes: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Axis 1 in Quartz's terms.
    public static let vertical = ScrollAxes(rawValue: 1 << 0)
    /// Axis 2.
    public static let horizontal = ScrollAxes(rawValue: 1 << 1)
    public static let both: ScrollAxes = [.vertical, .horizontal]
}

/// The six fields of a scroll event that carry its distance: a line delta
/// (whole wheel clicks), a fixed-point delta and a point delta, per axis.
/// Apps read different ones, so all of an axis's three are negated together.
public enum ScrollField: CaseIterable, Sendable {
    case lineVertical
    case lineHorizontal
    case fixedVertical
    case fixedHorizontal
    case pointVertical
    case pointHorizontal

    public var axis: ScrollAxes {
        switch self {
        case .lineVertical, .fixedVertical, .pointVertical: .vertical
        case .lineHorizontal, .fixedHorizontal, .pointHorizontal: .horizontal
        }
    }

    /// The fixed-point deltas are fractional; the others are integers.
    public var isFractional: Bool {
        self == .fixedVertical || self == .fixedHorizontal
    }

    public var eventField: CGEventField {
        switch self {
        case .lineVertical: .scrollWheelEventDeltaAxis1
        case .lineHorizontal: .scrollWheelEventDeltaAxis2
        case .fixedVertical: .scrollWheelEventFixedPtDeltaAxis1
        case .fixedHorizontal: .scrollWheelEventFixedPtDeltaAxis2
        case .pointVertical: .scrollWheelEventPointDeltaAxis1
        case .pointHorizontal: .scrollWheelEventPointDeltaAxis2
        }
    }
}

/// Something with scroll fields to read and write: a `CGEvent` in the
/// companion, a dictionary in the tests.
public protocol ScrollFieldAccess {
    func value(of field: ScrollField) -> Double
    func setValue(_ value: Double, of field: ScrollField)
}

public enum ScrollReversal {
    /// The fields to negate for `axes`, in the order they must be written.
    ///
    /// Setting a line delta makes macOS recompute that axis's point and
    /// fixed-point deltas from it, which would throw away a smooth scroll's
    /// fractional distance. So the line delta goes first and the other two
    /// overwrite what macOS derived.
    public static func fields(for axes: ScrollAxes) -> [ScrollField] {
        let order: [ScrollField] = [
            .lineVertical, .lineHorizontal,
            .fixedVertical, .fixedHorizontal,
            .pointVertical, .pointHorizontal,
        ]
        return order.filter { axes.contains($0.axis) }
    }

    /// Negates `axes` on `event`. Every value is read before any is written,
    /// because the first write changes the others.
    public static func reverse(_ axes: ScrollAxes, on event: some ScrollFieldAccess) {
        let fields = fields(for: axes)
        guard !fields.isEmpty else { return }
        let originals = fields.map { event.value(of: $0) }
        for (field, value) in zip(fields, originals) {
            event.setValue(-value, of: field)
        }
    }
}
