import Foundation
import Security

/// Google's OAuth 2.0 service-account flow: sign a short-lived assertion with
/// the account's private key, trade it for a bearer token.
///
/// An actor because the token is shared mutable state and several property
/// refreshes run concurrently — without serialisation they would each mint
/// their own token.
public actor GoogleTokenProvider {
    /// Covers both the Data API and the Admin API, so property discovery needs
    /// no second grant from the user.
    public static let scope = "https://www.googleapis.com/auth/analytics.readonly"
    public static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    /// Google issues one-hour tokens; the assertion asks for the same.
    static let assertionLifetime: TimeInterval = 3600
    /// Renew slightly early rather than discovering expiry as a 401 mid-refresh.
    static let renewalMargin: TimeInterval = 60

    private let account: ServiceAccount
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date

    private var token: String?
    private var expiry: Date?

    public init(
        account: ServiceAccount,
        transport: HTTPTransport,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.transport = transport
        self.now = now
    }

    public var clientEmail: String { account.clientEmail }

    /// Drops the cached token. Called when Google rejects one, so the next
    /// request re-authenticates rather than retrying the same dead credential.
    public func invalidate() {
        token = nil
        expiry = nil
    }

    public func accessToken() async throws -> String {
        if let token, let expiry, now().addingTimeInterval(Self.renewalMargin) < expiry {
            return token
        }

        let issuedAt = now()
        let assertion = try Self.assertion(
            for: account,
            issuedAt: issuedAt,
            scope: Self.scope,
            audience: Self.tokenEndpoint
        )

        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        ])

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw AnalyticsError.authenticationFailed(Self.errorDetail(from: data, status: response.statusCode))
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Double?
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AnalyticsError.malformedResponse
        }

        token = decoded.access_token
        expiry = issuedAt.addingTimeInterval(decoded.expires_in ?? Self.assertionLifetime)
        return decoded.access_token
    }

    // MARK: - Assertion

    /// Builds the signed JWT. `static` so it can be tested without a network
    /// stub or an actor hop.
    static func assertion(
        for account: ServiceAccount,
        issuedAt: Date,
        scope: String,
        audience: String
    ) throws -> String {
        let header = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": account.clientEmail,
            "scope": scope,
            "aud": audience,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(issuedAt.timeIntervalSince1970 + assertionLifetime),
        ]

        let signingInput = try [header as [String: Any], claims]
            .map { try base64URL(JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])) }
            .joined(separator: ".")

        let signature = try sign(Data(signingInput.utf8), pem: account.privateKeyPEM)
        return signingInput + "." + base64URL(signature)
    }

    static func sign(_ payload: Data, pem: String) throws -> Data {
        let pkcs1 = try DER.pkcs1PrivateKey(fromDER: DER.der(fromPEM: pem))
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
            throw AnalyticsError.unusableKey
        }
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, payload as CFData, nil
        ) else {
            throw AnalyticsError.unusableKey
        }
        return signature as Data
    }

    /// JWT uses base64url without padding.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    /// Google's token endpoint reports failures as `{"error":"invalid_grant",
    /// "error_description":"…"}`. The description is the part that says
    /// whether the key was revoked or the clock is wrong.
    private static func errorDetail(from data: Data, status: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "HTTP \(status)"
        }
        let code = object["error"] as? String
        let description = object["error_description"] as? String
        return [code, description].compactMap { $0 }.joined(separator: ": ").ifEmpty("HTTP \(status)")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
