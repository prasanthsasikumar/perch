import Foundation

/// Everything the user sets. Perch owns this file and writes it; the
/// companion only ever reads it.
public struct TapConfig: Codable, Equatable, Sendable {
    public var slots: [GestureSlot]
    public var sensitivity: Double
    public var tapGroupingWindow: Double
    /// Off: knocks are still recognised and shown, but run nothing.
    public var enabled: Bool
    public var invertSides: Bool
    public var ignoreWhileTyping: Bool
    public var showHUD: Bool
    public var actionCooldown: Double
    public var sideBias: Double
    public var soundEnabled: Bool
    public var soundPack: SoundPack
    public var soundVolume: Float
    public var hasCompletedOnboarding: Bool
    /// The panel's Listening switch. Saved so a pause survives a restart:
    /// the companion reads it at launch. Default on.
    public var listening: Bool
    public var appRules: [AppRule]
    public var layout: GestureLayout

    public static let `default` = TapConfig(
        slots: GesturePreset.daily.slots,
        sensitivity: 0.70,
        tapGroupingWindow: 0.40,
        enabled: true,
        invertSides: false,
        ignoreWhileTyping: true,
        showHUD: true,
        actionCooldown: 0.18,
        sideBias: 0,
        soundEnabled: false,
        soundPack: .drumKit,
        soundVolume: 0.7,
        hasCompletedOnboarding: false,
        listening: true,
        appRules: [
            AppRule(
                bundleID: "com.todesktop.230313mzl4w4u92",
                appName: "Cursor",
                slots: [
                    GestureSlot(side: .left, tapCount: 1, actionType: .aiAccept),
                    GestureSlot(side: .left, tapCount: 2, actionType: .aiReject),
                    GestureSlot(side: .left, tapCount: 3, actionType: .save),
                ]
            ),
            AppRule(
                bundleID: "com.anthropic.claudefordesktop",
                appName: "Claude",
                slots: [
                    GestureSlot(side: .left, tapCount: 1, actionType: .aiAccept),
                    GestureSlot(side: .left, tapCount: 2, actionType: .aiReject),
                ]
            ),
        ],
        layout: .knock
    )

    public init(
        slots: [GestureSlot],
        sensitivity: Double,
        tapGroupingWindow: Double,
        enabled: Bool,
        invertSides: Bool,
        ignoreWhileTyping: Bool,
        showHUD: Bool,
        actionCooldown: Double,
        sideBias: Double,
        soundEnabled: Bool,
        soundPack: SoundPack,
        soundVolume: Float,
        hasCompletedOnboarding: Bool,
        listening: Bool = true,
        appRules: [AppRule],
        layout: GestureLayout
    ) {
        self.slots = slots
        self.sensitivity = sensitivity
        self.tapGroupingWindow = tapGroupingWindow
        self.enabled = enabled
        self.invertSides = invertSides
        self.ignoreWhileTyping = ignoreWhileTyping
        self.showHUD = showHUD
        self.actionCooldown = actionCooldown
        self.sideBias = sideBias
        self.soundEnabled = soundEnabled
        self.soundPack = soundPack
        self.soundVolume = soundVolume
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.listening = listening
        self.appRules = appRules
        self.layout = layout
    }

    /// Every key is optional, so a file written by an older Perch, or one
    /// missing a setting added later, still loads with the rest intact.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        slots = try c.decodeIfPresent([GestureSlot].self, forKey: .slots) ?? fallback.slots
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? fallback.sensitivity
        tapGroupingWindow = try c.decodeIfPresent(Double.self, forKey: .tapGroupingWindow) ?? fallback.tapGroupingWindow
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        invertSides = try c.decodeIfPresent(Bool.self, forKey: .invertSides) ?? fallback.invertSides
        ignoreWhileTyping = try c.decodeIfPresent(Bool.self, forKey: .ignoreWhileTyping) ?? fallback.ignoreWhileTyping
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? fallback.showHUD
        actionCooldown = try c.decodeIfPresent(Double.self, forKey: .actionCooldown) ?? fallback.actionCooldown
        sideBias = try c.decodeIfPresent(Double.self, forKey: .sideBias) ?? fallback.sideBias
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? fallback.soundEnabled
        soundPack = (try? c.decodeIfPresent(SoundPack.self, forKey: .soundPack)) ?? fallback.soundPack
        soundVolume = try c.decodeIfPresent(Float.self, forKey: .soundVolume) ?? fallback.soundVolume
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? fallback.hasCompletedOnboarding
        listening = try c.decodeIfPresent(Bool.self, forKey: .listening) ?? fallback.listening
        appRules = try c.decodeIfPresent([AppRule].self, forKey: .appRules) ?? fallback.appRules
        layout = (try? c.decodeIfPresent(GestureLayout.self, forKey: .layout)) ?? fallback.layout
        // A map missing any of its six cells is not one a knock can rely on.
        if Set(slots.map(\.id)).count < 6 {
            slots = fallback.slots
        }
    }

    // MARK: - The gesture map

    public var currentPreset: GesturePreset? { GesturePreset.matching(slots) }

    public mutating func applyPreset(_ preset: GesturePreset) {
        slots = preset.slots
    }

    public func slot(side: TapSide, tapCount: Int) -> GestureSlot? {
        slots.first { $0.side == side && $0.tapCount == tapCount }
    }

    /// What a knock does with this app in front. "Anywhere" ignores the side:
    /// its three actions are the left side's, and an app rule's left-side
    /// overrides replace them.
    public func resolvedSlot(side: TapSide, tapCount: Int, bundleID: String?) -> GestureSlot? {
        let rule = bundleID.flatMap { id in appRules.first { $0.enabled && $0.bundleID == id } }
        if layout == .knock {
            if let override = rule?.slots.first(where: { $0.tapCount == tapCount }) {
                return override
            }
            return slot(side: .left, tapCount: tapCount)
        }
        if let override = rule?.override(side: side, tapCount: tapCount) {
            return override
        }
        return slot(side: side, tapCount: tapCount)
    }

    /// Keeps what the user has learned and the counts, resets everything else.
    public func reset() -> TapConfig {
        var fresh = Self.default
        fresh.hasCompletedOnboarding = hasCompletedOnboarding
        return fresh
    }

    // MARK: - Sensitivity

    /// The knock threshold in g that `sensitivity` maps to.
    public var threshold: Double {
        TapDetector.threshold(sensitivity: sensitivity)
    }

    public var sensitivityLabel: String {
        if sensitivity < 0.35 { return "Firm taps" }
        if sensitivity < 0.7 { return "Balanced" }
        return "Light taps"
    }

    // MARK: - Calibration

    /// From the side readings of four knocks on each edge: whether this
    /// chassis reads mirrored, and the offset that centres the two.
    public static func calibration(leftPeaks: [Double], rightPeaks: [Double]) -> (invertSides: Bool, sideBias: Double)? {
        guard !leftPeaks.isEmpty, !rightPeaks.isEmpty else { return nil }
        let leftMean = leftPeaks.reduce(0, +) / Double(leftPeaks.count)
        let rightMean = rightPeaks.reduce(0, +) / Double(rightPeaks.count)
        return (leftMean > rightMean, -(leftMean + rightMean) / 2)
    }
}
