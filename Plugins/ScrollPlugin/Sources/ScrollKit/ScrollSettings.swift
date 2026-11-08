import Foundation

/// Everything the user sets. Perch owns this file and writes it; the
/// companion only ever reads it.
public struct ScrollSettings: Codable, Equatable, Sendable {
    /// The panel's master switch. Off: every scroll passes through untouched.
    public var isOn: Bool
    /// A wheel mouse, or anything else that scrolls without phases.
    public var reverseMouse: Bool
    /// The built-in trackpad, a Magic Trackpad, or a Magic Mouse.
    public var reverseTrackpad: Bool
    /// Up and down.
    public var reverseVertical: Bool
    /// Left and right, including Shift-scroll on a wheel.
    public var reverseHorizontal: Bool
    /// Perch switches a new plugin on for everyone who upgrades, so nothing is
    /// reversed until the user has been through the panel's setup.
    public var hasCompletedSetup: Bool

    /// Natural scrolling is one switch in macOS and applies to every device.
    /// Most people who want this plugin have it on and want the wheel back
    /// the classic way, so the wheel is reversed and the trackpad left alone.
    public static let `default` = ScrollSettings(
        isOn: true,
        reverseMouse: true,
        reverseTrackpad: false,
        reverseVertical: true,
        reverseHorizontal: true,
        hasCompletedSetup: false
    )

    public init(
        isOn: Bool,
        reverseMouse: Bool,
        reverseTrackpad: Bool,
        reverseVertical: Bool,
        reverseHorizontal: Bool,
        hasCompletedSetup: Bool
    ) {
        self.isOn = isOn
        self.reverseMouse = reverseMouse
        self.reverseTrackpad = reverseTrackpad
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.hasCompletedSetup = hasCompletedSetup
    }

    /// A key missing from the file takes its default, so a file written by an
    /// older Perch still reads after a setting is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? fallback.isOn
        reverseMouse = try c.decodeIfPresent(Bool.self, forKey: .reverseMouse) ?? fallback.reverseMouse
        reverseTrackpad = try c.decodeIfPresent(Bool.self, forKey: .reverseTrackpad) ?? fallback.reverseTrackpad
        reverseVertical = try c.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? fallback.reverseVertical
        reverseHorizontal = try c.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? fallback.reverseHorizontal
        hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? fallback.hasCompletedSetup
    }

    /// Whether the companion should be changing anything at all. When this is
    /// false it does not install its event tap, so scrolls never pass through it.
    public var isReversing: Bool {
        isOn && hasCompletedSetup && (reverseMouse || reverseTrackpad) && (reverseVertical || reverseHorizontal)
    }

    /// The axes a scroll from `device` has reversed. Empty: leave it alone.
    public func axesToReverse(for device: ScrollDevice) -> ScrollAxes {
        guard isOn, hasCompletedSetup else { return [] }
        switch device {
        case .mouse: guard reverseMouse else { return [] }
        case .trackpad: guard reverseTrackpad else { return [] }
        }
        var axes: ScrollAxes = []
        if reverseVertical { axes.insert(.vertical) }
        if reverseHorizontal { axes.insert(.horizontal) }
        return axes
    }
}
