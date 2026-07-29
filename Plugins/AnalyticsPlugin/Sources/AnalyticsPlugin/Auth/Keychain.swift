import Foundation
import Security

/// Where the one secret this plugin holds is kept.
///
/// A protocol with a single implementation looks like ceremony until you try
/// to test the store: without it, every test of caching or refresh behaviour
/// would write to the developer's real login keychain.
public protocol CredentialStore: Sendable {
    /// `nil` when nothing has been stored, which is the ordinary "not set up
    /// yet" case rather than an error.
    func load() throws -> Data?
    func save(_ data: Data) throws
    func remove() throws
}

/// A single generic-password item in the login keychain.
public struct KeychainCredentialStore: CredentialStore {
    public enum Failure: Error, Equatable {
        case status(OSStatus)

        /// `errSecMissingEntitlement` is the one worth naming: it means this
        /// build cannot reach a keychain at all, which is a very different
        /// conversation from a missing item.
        public var isUnavailable: Bool {
            if case .status(let code) = self { return code == errSecMissingEntitlement }
            return false
        }
    }

    let service: String
    let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func save(_ data: Data) throws {
        // Delete-then-add rather than SecItemUpdate: the update path needs a
        // different query shape depending on whether the item already exists,
        // and this runs once per credential import.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    public func load() throws -> Data? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.status(status) }
        return result as? Data
    }

    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }
}
