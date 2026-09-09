import Foundation

public struct SnapshotRequest: Sendable {
    public let url: URL
    public let username: String?
    public let password: String?

    public init(url: URL, username: String?, password: String?) {
        self.url = url
        self.username = username
        self.password = password
    }
}

/// Where a reading comes from. One implementation talks to a real agent; the
/// tests supply their own, which is the whole reason this exists.
public protocol SnapshotSource: Sendable {
    func fetch(_ request: SnapshotRequest) async throws -> HostSnapshot
}
