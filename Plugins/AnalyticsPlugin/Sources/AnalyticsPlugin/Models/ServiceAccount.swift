import Foundation

/// The two fields of a Google service-account key file this plugin needs.
///
/// The rest of the file — project id, key id, the various URLs — is constant
/// across every service account Google issues, so keeping it would be storing
/// a secret's worth of risk for none of its value.
public struct ServiceAccount: Codable, Equatable, Sendable {
    public let clientEmail: String
    /// PEM, exactly as Google wrote it, newlines and all.
    public let privateKeyPEM: String

    public init(clientEmail: String, privateKeyPEM: String) {
        self.clientEmail = clientEmail
        self.privateKeyPEM = privateKeyPEM
    }

    /// Parses the JSON Google hands you from the Cloud console.
    public init(keyFile data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalyticsError.malformedKey("not JSON")
        }
        // Checked before the fields, because an OAuth *client* JSON has neither
        // and "missing client_email" would send the user looking for the wrong
        // problem in the right file.
        if let type = object["type"] as? String, type != "service_account" {
            throw AnalyticsError.malformedKey("type is \(type), not service_account")
        }
        guard let email = object["client_email"] as? String, !email.isEmpty else {
            throw AnalyticsError.malformedKey("no client_email")
        }
        guard let key = object["private_key"] as? String, key.contains("PRIVATE KEY") else {
            throw AnalyticsError.malformedKey("no private_key")
        }
        self.init(clientEmail: email, privateKeyPEM: key)
    }
}
