import Foundation

/// One machine being watched.
///
/// The password is deliberately not here: this struct is written to disk as
/// plain JSON, and a credential belongs in the Keychain. `ServerStore` holds
/// the two together.
public struct ServerTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What the user calls it. Defaults to the URL's host.
    public var name: String
    /// The agent's base URL, already normalised to end at `/api/now`.
    public var endpoint: URL
    /// `nil` when the endpoint needs no basic auth.
    public var username: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        endpoint: URL,
        username: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.username = username
        self.createdAt = createdAt
    }

    /// What the card shows under the name, and what error messages name.
    public var displayHost: String {
        endpoint.host ?? endpoint.absoluteString
    }
}
