import Foundation

public struct BusySettings: Codable, Equatable {
    /// Below this Google starts to notice. Live busyness itself only moves
    /// every few minutes, so nothing is lost by waiting.
    public static let minimumRefreshMinutes = 5

    public var refreshIntervalMinutes: Int

    public init(refreshIntervalMinutes: Int = 10) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    public static let defaults = BusySettings()

    /// The interval the loop actually uses: the setting, floored.
    public var refreshInterval: TimeInterval {
        TimeInterval(max(refreshIntervalMinutes, Self.minimumRefreshMinutes) * 60)
    }
}
