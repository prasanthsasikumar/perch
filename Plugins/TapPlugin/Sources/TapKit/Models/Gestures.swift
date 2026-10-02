import Foundation

public enum TapSide: String, Codable, CaseIterable, Sendable {
    case left
    case right

    public var displayName: String { rawValue.capitalized }

    public var opposite: TapSide { self == .left ? .right : .left }
}

/// "Single", "Double", "Triple".
public func tapWord(_ count: Int) -> String {
    switch count {
    case 1: "Single"
    case 2: "Double"
    default: "Triple"
    }
}

/// One cell of the gesture map: a side and a knock count, and what it does.
public struct GestureSlot: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(side.rawValue)_\(tapCount)" }
    public var side: TapSide
    public var tapCount: Int
    public var actionType: ActionType
    public var parameter: String

    public init(side: TapSide, tapCount: Int, actionType: ActionType, parameter: String = "") {
        self.side = side
        self.tapCount = tapCount
        self.actionType = actionType
        self.parameter = parameter
    }

    public var summary: String {
        if actionType == .none { return "Off" }
        if actionType.needsParameter, !parameter.isEmpty {
            return "\(actionType.displayName) · \(parameter)"
        }
        return actionType.displayName
    }

    public func label(layout: GestureLayout) -> String {
        switch layout {
        case .knock: tapWord(tapCount)
        case .sides: "\(side.displayName) · \(tapWord(tapCount))"
        }
    }
}

/// Knocks that mean something else while one app is in front.
public struct AppRule: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var enabled: Bool
    /// Present slots override the global map. Missing slots inherit.
    public var slots: [GestureSlot]

    public init(
        id: UUID = UUID(),
        bundleID: String,
        appName: String,
        enabled: Bool = true,
        slots: [GestureSlot] = []
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.enabled = enabled
        self.slots = slots
    }

    public func override(side: TapSide, tapCount: Int) -> GestureSlot? {
        slots.first { $0.side == side && $0.tapCount == tapCount }
    }
}

public enum GestureLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One, two or three knocks anywhere; the side is ignored.
    case knock
    /// The left and right edges are separate sets of actions.
    case sides

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .knock: "Anywhere"
        case .sides: "Left & Right"
        }
    }

    public var subtitle: String {
        switch self {
        case .knock: "One, two, or three taps on the chassis or desk"
        case .sides: "Separate actions for each edge"
        }
    }
}

public enum GesturePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily
    case coding
    case capture
    case media
    case focus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .coding: "Coding"
        case .capture: "Capture"
        case .media: "Media"
        case .focus: "Focus"
        }
    }

    /// The three "Anywhere" actions, which are the left side's.
    public var knockLine: String {
        slots.filter { $0.side == .left }
            .sorted { $0.tapCount < $1.tapCount }
            .map(\.actionType.displayName)
            .joined(separator: " · ")
    }

    public var subtitle: String {
        switch self {
        case .daily: "Copy, paste, play, screenshot, lock"
        case .coding: "Accept, reject, save — built for Cursor and Claude"
        case .capture: "Full and partial screenshots"
        case .media: "Play, skip, volume"
        case .focus: "Hide, tile, lock, sleep"
        }
    }

    public var icon: String {
        switch self {
        case .daily: "star.fill"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .capture: "camera.viewfinder"
        case .media: "playpause"
        case .focus: "moon.fill"
        }
    }

    public var slots: [GestureSlot] {
        let (left, right): ([ActionType], [ActionType]) = switch self {
        case .daily: ([.copy, .paste, .undo], [.mediaPlayPause, .screenshot, .lockScreen])
        case .coding: ([.aiAccept, .aiReject, .save], [.copy, .paste, .undo])
        case .capture: ([.screenshot, .screenshotSelection, .lockScreen], [.mediaPlayPause, .mediaNext, .mute])
        case .media: ([.mediaPrevious, .volumeDown, .mute], [.mediaPlayPause, .mediaNext, .volumeUp])
        case .focus: ([.hideFrontApp, .tileLeft, .lockScreen], [.missionControl, .tileRight, .sleepDisplay])
        }
        return left.enumerated().map { GestureSlot(side: .left, tapCount: $0.offset + 1, actionType: $0.element) }
            + right.enumerated().map { GestureSlot(side: .right, tapCount: $0.offset + 1, actionType: $0.element) }
    }

    public static func matching(_ slots: [GestureSlot]) -> GesturePreset? {
        allCases.first { signature($0.slots) == signature(slots) }
    }

    private static func signature(_ slots: [GestureSlot]) -> String {
        slots
            .sorted { ($0.side.rawValue, $0.tapCount) < ($1.side.rawValue, $1.tapCount) }
            .map { "\($0.side.rawValue).\($0.tapCount).\($0.actionType.rawValue).\($0.parameter)" }
            .joined(separator: "|")
    }
}

/// Counts kept by the companion, which is what sees the knocks.
public struct GestureStats: Codable, Equatable, Sendable {
    public var gesturesFired = 0
    public var tapsDetected = 0
    public var lastDayStamp = ""
    public var todayCount = 0

    public init() {}

    public mutating func record(tapCount: Int, on date: Date = Date()) {
        let stamp = Self.dayStamp(date)
        if stamp != lastDayStamp {
            lastDayStamp = stamp
            todayCount = 0
        }
        gesturesFired += 1
        tapsDetected += tapCount
        todayCount += 1
    }

    /// Today's count, or zero if the last knock was on another day.
    public func today(_ date: Date = Date()) -> Int {
        lastDayStamp == Self.dayStamp(date) ? todayCount : 0
    }

    static func dayStamp(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
