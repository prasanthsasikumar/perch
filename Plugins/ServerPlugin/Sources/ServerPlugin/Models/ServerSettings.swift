import Foundation

public struct ServerSettings: Codable, Equatable, Sendable {
    /// A menu bar app polling a box it is meant to be watching over should not
    /// itself be a load. The agent samples every 10s regardless; asking more
    /// often than this only costs both ends bandwidth.
    public static let minimumRefreshSeconds = 15

    public var refreshIntervalSeconds: Int

    public init(refreshIntervalSeconds: Int = 60) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }

    public static let defaults = ServerSettings()

    /// The interval the loop actually uses: the setting, floored.
    public var refreshInterval: TimeInterval {
        TimeInterval(max(refreshIntervalSeconds, Self.minimumRefreshSeconds))
    }
}
