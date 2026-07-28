import PerchKit
import XCTest

final class PluginDefaultsTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMissingKeysReturnTheProvidedDefault() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        XCTAssertTrue(defaults.bool("enabled", default: true))
        XCTAssertEqual(defaults.integer("count", default: 7), 7)
        XCTAssertNil(defaults.string("token"))
    }

    func testValuesRoundTrip() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        defaults.set(false, for: "enabled")
        defaults.set(3, for: "count")
        defaults.set("abc", for: "token")
        XCTAssertFalse(defaults.bool("enabled", default: true))
        XCTAssertEqual(defaults.integer("count", default: 7), 3)
        XCTAssertEqual(defaults.string("token"), "abc")
    }

    func testTwoPrefixesDoNotCollideOnTheSameKey() {
        let a = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        let b = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.b")
        a.set(1, for: "count")
        b.set(2, for: "count")
        XCTAssertEqual(a.integer("count", default: 0), 1)
        XCTAssertEqual(b.integer("count", default: 0), 2)
    }

    func testSettingAStringToNilClearsIt() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        defaults.set("abc", for: "token")
        defaults.set(nil, for: "token")
        XCTAssertNil(defaults.string("token"))
    }
}
