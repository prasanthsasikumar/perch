import Security
import XCTest
@testable import AnalyticsPlugin

final class ServiceAccountTests: XCTestCase {
    func testParsesAGoogleKeyFile() throws {
        let account = try ServiceAccount(keyFile: try Fixture.serviceAccountJSON())
        XCTAssertEqual(account.clientEmail, "perch@example.iam.gserviceaccount.com")
        XCTAssertTrue(account.privateKeyPEM.contains("BEGIN PRIVATE KEY"))
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try ServiceAccount(keyFile: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? AnalyticsError, .malformedKey("not JSON"))
        }
    }

    /// An OAuth *client* JSON has neither field, and "no client_email" would
    /// send the user hunting for the wrong problem in the right file.
    func testRejectsAnOAuthClientFileByType() {
        let json = try! JSONSerialization.data(withJSONObject: [
            "type": "authorized_user", "client_id": "x",
        ])
        XCTAssertThrowsError(try ServiceAccount(keyFile: json)) { error in
            XCTAssertEqual(
                error as? AnalyticsError,
                .malformedKey("type is authorized_user, not service_account")
            )
        }
    }

    func testRejectsAKeyFileWithNoPrivateKey() {
        let json = try! JSONSerialization.data(withJSONObject: [
            "type": "service_account", "client_email": "a@b.com",
        ])
        XCTAssertThrowsError(try ServiceAccount(keyFile: json)) { error in
            XCTAssertEqual(error as? AnalyticsError, .malformedKey("no private_key"))
        }
    }

    func testRoundTripsThroughCodable() throws {
        let account = try ServiceAccount(keyFile: try Fixture.serviceAccountJSON())
        let decoded = try JSONDecoder().decode(
            ServiceAccount.self, from: try JSONEncoder().encode(account)
        )
        XCTAssertEqual(decoded, account)
    }
}

final class DERTests: XCTestCase {
    /// The step this whole file exists for: Google ships PKCS#8 and
    /// `SecKeyCreateWithData` wants PKCS#1.
    func testUnwrapsPKCS8ToPKCS1() throws {
        let der = try DER.der(fromPEM: try RSATestKey.pkcs8PEM())
        XCTAssertEqual(try DER.pkcs1PrivateKey(fromDER: der), try RSATestKey.pkcs1DER())
    }

    /// A key that is already PKCS#1 must pass through untouched rather than
    /// having its modulus mistaken for an algorithm identifier.
    func testLeavesPKCS1Alone() throws {
        let der = try DER.der(fromPEM: try RSATestKey.pkcs1PEM())
        XCTAssertEqual(try DER.pkcs1PrivateKey(fromDER: der), try RSATestKey.pkcs1DER())
    }

    func testUnwrappedKeyIsAcceptedBySecurityFramework() throws {
        let pkcs1 = try DER.pkcs1PrivateKey(fromDER: try DER.der(fromPEM: try RSATestKey.pkcs8PEM()))
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        XCTAssertNotNil(SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil))
    }

    func testStripsArmourAndWhitespace() throws {
        let pem = try RSATestKey.pkcs8PEM()
        XCTAssertEqual(try DER.der(fromPEM: pem), try DER.der(fromPEM: pem + "\n"))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try DER.der(fromPEM: "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----"))
        XCTAssertThrowsError(try DER.pkcs1PrivateKey(fromDER: Data([0x30, 0x02, 0x01])))
    }

    /// A truncated length header must fail rather than read past the buffer.
    func testRejectsATruncatedLength() {
        XCTAssertThrowsError(try DER.element(in: Data([0x30, 0x84, 0x00]), at: 0))
    }
}
