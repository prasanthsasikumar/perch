import Foundation
import Security

/// Where each server's basic-auth password lives.
///
/// Keyed by the target's id rather than its hostname, so renaming or
/// re-pointing a target keeps its password, and two entries for the same host
/// stay separate.
///
/// This deliberately does not reuse `AnalyticsPlugin`'s Keychain type: plugins
/// are independent packages, and one plugin importing another to borrow a
/// helper would couple them for the sake of sixty lines. If a third plugin
/// needs a keychain, that is the moment to lift one into PerchKit.
public protocol ServerCredentialStore: Sendable {
    func password(for id: UUID) -> String?
    func setPassword(_ password: String?, for id: UUID)
    func removePassword(for id: UUID)
}

public struct KeychainServerCredentials: ServerCredentialStore {
    private let service: String

    public init(service: String = "org.ahlab.perch.server") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    public func password(for id: UUID) -> String? {
        var attributes = query(id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String?, for id: UUID) {
        guard let password, !password.isEmpty else {
            removePassword(for: id)
            return
        }
        // Delete-then-add rather than SecItemUpdate: the update path needs a
        // different query shape depending on whether the item already exists,
        // and this runs once per password change.
        SecItemDelete(query(id) as CFDictionary)
        var attributes = query(id)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func removePassword(for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}

/// For tests and previews. Never touches the login keychain.
public final class InMemoryServerCredentials: ServerCredentialStore, @unchecked Sendable {
    private var storage: [UUID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func password(for id: UUID) -> String? {
        lock.withLock { storage[id] }
    }

    public func setPassword(_ password: String?, for id: UUID) {
        lock.withLock { storage[id] = password }
    }

    public func removePassword(for id: UUID) {
        lock.withLock { storage[id] = nil }
    }
}
