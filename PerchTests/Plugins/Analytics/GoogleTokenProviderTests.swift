import XCTest
@testable import AnalyticsPlugin

final class GoogleTokenProviderTests: XCTestCase {
    private func account() throws -> ServiceAccount {
        try ServiceAccount(keyFile: try Fixture.serviceAccountJSON())
    }

    private func tokenBody(_ token: String, expiresIn: Double = 3600) -> Data {
        Data(#"{"access_token":"\#(token)","expires_in":\#(Int(expiresIn)),"token_type":"Bearer"}"#.utf8)
    }

    // MARK: - Assertion

    func testAssertionHasThreeBase64URLSegments() throws {
        let assertion = try GoogleTokenProvider.assertion(
            for: try account(),
            issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
            scope: GoogleTokenProvider.scope,
            audience: GoogleTokenProvider.tokenEndpoint
        )

        let segments = assertion.split(separator: ".")
        XCTAssertEqual(segments.count, 3)
        // base64url, so none of the base64 characters JWT forbids.
        XCTAssertFalse(assertion.contains("+"))
        XCTAssertFalse(assertion.contains("/"))
        XCTAssertFalse(assertion.contains("="))
    }

    func testAssertionClaimsAreWhatGoogleExpects() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let assertion = try GoogleTokenProvider.assertion(
            for: try account(),
            issuedAt: issuedAt,
            scope: GoogleTokenProvider.scope,
            audience: GoogleTokenProvider.tokenEndpoint
        )
        let segments = assertion.split(separator: ".")

        let header = try decodeSegment(segments[0])
        XCTAssertEqual(header["alg"] as? String, "RS256")
        XCTAssertEqual(header["typ"] as? String, "JWT")

        let claims = try decodeSegment(segments[1])
        XCTAssertEqual(claims["iss"] as? String, "perch@example.iam.gserviceaccount.com")
        XCTAssertEqual(claims["aud"] as? String, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(claims["scope"] as? String, "https://www.googleapis.com/auth/analytics.readonly")
        XCTAssertEqual(claims["iat"] as? Int, 1_800_000_000)
        // One hour, and expiry measured from issue rather than from now.
        XCTAssertEqual(claims["exp"] as? Int, 1_800_000_000 + 3600)
    }

    /// A signature is only worth anything if the corresponding public key
    /// verifies it.
    func testSignatureVerifiesAgainstThePublicKey() throws {
        let payload = Data("perch".utf8)
        let signature = try GoogleTokenProvider.sign(payload, pem: try RSATestKey.pkcs8PEM())

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        let privateKey = SecKeyCreateWithData(
            try RSATestKey.pkcs1DER() as CFData, attributes as CFDictionary, nil
        )!
        let publicKey = SecKeyCopyPublicKey(privateKey)!

        XCTAssertTrue(SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            payload as CFData, signature as CFData, nil
        ))
    }

    // MARK: - Token exchange

    func testExchangesTheAssertionForABearerToken() async throws {
        let transport = StubTransport(body: tokenBody("token-1"))
        let provider = GoogleTokenProvider(account: try account(), transport: transport)

        let token = try await provider.accessToken()

        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(transport.requests.count, 1)
        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"))
        XCTAssertTrue(body.contains("assertion="))
    }

    /// Six reports across two properties must not mint six tokens.
    func testTokenIsReusedUntilItNearsExpiry() async throws {
        let clock = Clock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let transport = StubTransport(responder: { index in
            (Data(#"{"access_token":"token-\#(index)","expires_in":3600}"#.utf8), 200)
        })
        let provider = GoogleTokenProvider(
            account: try account(), transport: transport, now: { clock.now }
        )

        let first = try await provider.accessToken()
        clock.advance(by: 1800)
        let second = try await provider.accessToken()

        XCTAssertEqual(first, "token-0")
        XCTAssertEqual(second, "token-0")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testTokenIsRefetchedOnceItExpires() async throws {
        let clock = Clock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let transport = StubTransport(responder: { index in
            (Data(#"{"access_token":"token-\#(index)","expires_in":3600}"#.utf8), 200)
        })
        let provider = GoogleTokenProvider(
            account: try account(), transport: transport, now: { clock.now }
        )

        let first = try await provider.accessToken()
        // Past the renewal margin, so the cached token is treated as spent
        // rather than being discovered dead as a 401 mid-refresh.
        clock.advance(by: 3600)
        let second = try await provider.accessToken()

        XCTAssertEqual(first, "token-0")
        XCTAssertEqual(second, "token-1")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testInvalidateForcesAFreshToken() async throws {
        let transport = StubTransport(responder: { index in
            (Data(#"{"access_token":"token-\#(index)","expires_in":3600}"#.utf8), 200)
        })
        let provider = GoogleTokenProvider(account: try account(), transport: transport)

        _ = try await provider.accessToken()
        await provider.invalidate()
        let refreshed = try await provider.accessToken()

        XCTAssertEqual(refreshed, "token-1")
    }

    /// `invalid_grant` is what a revoked key or a badly wrong clock looks
    /// like, and the description is the part that tells them apart.
    func testRejectedAssertionSurfacesGooglesDescription() async throws {
        let transport = StubTransport(
            body: Data(#"{"error":"invalid_grant","error_description":"Invalid JWT Signature."}"#.utf8),
            status: 400
        )
        let provider = GoogleTokenProvider(account: try account(), transport: transport)

        do {
            _ = try await provider.accessToken()
            XCTFail("expected authentication to fail")
        } catch {
            XCTAssertEqual(
                error as? AnalyticsError,
                .authenticationFailed("invalid_grant: Invalid JWT Signature.")
            )
        }
    }

    func testUnparseableTokenResponseIsReportedAsSuch() async throws {
        let transport = StubTransport(body: Data(#"{"unexpected":true}"#.utf8))
        let provider = GoogleTokenProvider(account: try account(), transport: transport)

        do {
            _ = try await provider.accessToken()
            XCTFail("expected decoding to fail")
        } catch {
            XCTAssertEqual(error as? AnalyticsError, .malformedResponse)
        }
    }

    // MARK: - Helpers

    private func decodeSegment(_ segment: Substring) throws -> [String: Any] {
        var base64 = String(segment)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// A clock the test moves by hand.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(now: Date) { _now = now }

    var now: Date { lock.withLock { _now } }

    func advance(by interval: TimeInterval) {
        lock.withLock { _now = _now.addingTimeInterval(interval) }
    }
}
