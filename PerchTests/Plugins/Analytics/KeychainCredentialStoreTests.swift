import XCTest
@testable import AnalyticsPlugin

/// The one test here that touches real system state, deliberately.
///
/// These run hosted inside `Perch.app`, so they exercise the keychain under
/// exactly the sandbox and the ad-hoc signature the shipped build has. That is
/// the whole point: `errSecMissingEntitlement` is a configuration failure that
/// no amount of mocking would ever catch, and it would land on the user as
/// "importing my key silently does nothing".
///
/// A per-run service name keeps this out of the way of the real credential,
/// and `tearDown` removes it.
final class KeychainCredentialStoreTests: XCTestCase {
    private var store: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        store = KeychainCredentialStore(
            service: "org.ahlab.perch.analytics.tests.\(UUID().uuidString)",
            account: "serviceAccount"
        )
    }

    override func tearDown() {
        try? store.remove()
        store = nil
        super.tearDown()
    }

    func testNothingStoredReadsAsNilRatherThanAnError() throws {
        XCTAssertNil(try store.load())
    }

    func testSavedDataComesBack() throws {
        try store.save(Data("a-service-account-key".utf8))
        XCTAssertEqual(try store.load(), Data("a-service-account-key".utf8))
    }

    /// Replacing a key must overwrite rather than leave two items and return
    /// whichever the keychain happens to hand back first.
    func testSavingTwiceReplaces() throws {
        try store.save(Data("first".utf8))
        try store.save(Data("second".utf8))
        XCTAssertEqual(try store.load(), Data("second".utf8))
    }

    func testRemoveIsIdempotent() throws {
        try store.save(Data("key".utf8))
        try store.remove()
        XCTAssertNil(try store.load())
        // Removing what is already gone is the normal path when a user hits
        // Remove twice, not an error worth surfacing.
        XCTAssertNoThrow(try store.remove())
    }

    func testTwoServicesDoNotCollide() throws {
        let other = KeychainCredentialStore(
            service: "org.ahlab.perch.analytics.tests.other.\(UUID().uuidString)",
            account: "serviceAccount"
        )
        defer { try? other.remove() }

        try store.save(Data("mine".utf8))
        try other.save(Data("theirs".utf8))

        XCTAssertEqual(try store.load(), Data("mine".utf8))
        XCTAssertEqual(try other.load(), Data("theirs".utf8))
    }
}
