import Foundation

/// Everything the plugin keeps on disk, as one JSON document.
///
/// The last snapshot per server is kept so the panel opens on real numbers
/// rather than a spinner, dimmed until the first refresh lands.
public struct ServerDocument: Codable, Equatable, Sendable {
    public var servers: [ServerTarget]
    public var snapshots: [UUID: HostSnapshot]
    public var trends: [UUID: [TrendPoint]]
    public var settings: ServerSettings
    public var lastRefreshed: Date?

    public init(
        servers: [ServerTarget] = [],
        snapshots: [UUID: HostSnapshot] = [:],
        trends: [UUID: [TrendPoint]] = [:],
        settings: ServerSettings = .defaults,
        lastRefreshed: Date? = nil
    ) {
        self.servers = servers
        self.snapshots = snapshots
        self.trends = trends
        self.settings = settings
        self.lastRefreshed = lastRefreshed
    }
}

/// One point on a card's sparkline.
///
/// Perch keeps its own short history rather than pulling the agent's
/// `/api/history`: that endpoint returns every column for every sample, which
/// is hundreds of kilobytes for a day, and this link is slow enough that it
/// would dominate the refresh. The cost is that the trend only covers what
/// Perch has watched, which the panel says out loud.
public struct TrendPoint: Codable, Equatable, Sendable {
    public var at: Date
    public var cpu: Double
    public var load: Double
    public var memory: Double

    public init(at: Date, cpu: Double, load: Double, memory: Double) {
        self.at = at
        self.cpu = cpu
        self.load = load
        self.memory = memory
    }
}
