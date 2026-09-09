@testable import ServerPlugin
import XCTest

final class EndpointURLTests: XCTestCase {
    func testAppendsAPIPathToARoot() {
        XCTAssertEqual(
            EndpointURL.normalise("https://status.example.com")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testToleratesATrailingSlash() {
        XCTAssertEqual(
            EndpointURL.normalise("https://status.example.com/")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testLeavesAnAlreadyCompleteEndpointAlone() {
        XCTAssertEqual(
            EndpointURL.normalise("https://status.example.com/api/now")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testAssumesHTTPSForABareHostname() {
        XCTAssertEqual(
            EndpointURL.normalise("status.example.com")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testKeepsAnExplicitHTTPScheme() {
        XCTAssertEqual(
            EndpointURL.normalise("http://192.168.1.10:9110")?.absoluteString,
            "http://192.168.1.10:9110/api/now"
        )
    }

    func testKeepsASubPath() {
        XCTAssertEqual(
            EndpointURL.normalise("https://example.com/vps")?.absoluteString,
            "https://example.com/vps/api/now"
        )
    }

    /// A password in the URL would otherwise be written to disk in the plain
    /// JSON document alongside the rest of the target.
    func testStripsCredentialsFromThePastedURL() {
        let url = EndpointURL.normalise("https://user:secret@status.example.com")
        XCTAssertEqual(url?.absoluteString, "https://status.example.com/api/now")
        XCTAssertNil(url?.user)
        XCTAssertNil(url?.password)
    }

    func testStripsQueryAndFragment() {
        XCTAssertEqual(
            EndpointURL.normalise("https://status.example.com/?tab=cpu#top")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testRejectsEmptyAndNonsense() {
        XCTAssertNil(EndpointURL.normalise(""))
        XCTAssertNil(EndpointURL.normalise("   "))
        XCTAssertNil(EndpointURL.normalise("ftp://example.com"))
        XCTAssertNil(EndpointURL.normalise("https://"))
    }

    func testDashboardURLDropsTheAPIPath() {
        let endpoint = EndpointURL.normalise("https://status.example.com")!
        XCTAssertEqual(
            EndpointURL.dashboardURL(for: endpoint).absoluteString,
            "https://status.example.com"
        )
    }
}

/// The bug this class exists for: a server was added as `http://host`, macOS
/// refused the cleartext connection, and the panel reported "Couldn't reach",
/// which pointed the diagnosis at the server rather than at the scheme.
final class EndpointSchemeTests: XCTestCase {
    func testPublicHTTPIsUpgradedToHTTPS() {
        XCTAssertEqual(
            EndpointURL.normalise("http://status.example.com")?.absoluteString,
            "https://status.example.com/api/now"
        )
    }

    func testUpgradeSurvivesAPathAndPort() {
        XCTAssertEqual(
            EndpointURL.normalise("http://status.example.com:8443/vps")?.absoluteString,
            "https://status.example.com:8443/vps/api/now"
        )
    }

    /// An SSH tunnel to the agent is the documented way to reach it without a
    /// proxy, and ATS permits loopback, so http must survive there.
    func testLoopbackKeepsHTTP() {
        for address in ["http://127.0.0.1:9110", "http://localhost:9110"] {
            XCTAssertTrue(
                EndpointURL.normalise(address)?.scheme == "http",
                "\(address) should stay http"
            )
        }
    }

    func testPrivateNetworkKeepsHTTP() {
        for address in ["http://192.168.1.10:9110", "http://10.0.0.5", "http://172.16.4.4",
                        "http://nas.local:9110"] {
            XCTAssertEqual(EndpointURL.normalise(address)?.scheme, "http", address)
        }
    }

    /// 172.32 is outside the private range and is a public address.
    func testAddressesOutsideThePrivateRangeAreUpgraded() {
        XCTAssertEqual(EndpointURL.normalise("http://172.32.0.1")?.scheme, "https")
        XCTAssertEqual(EndpointURL.normalise("http://172.15.0.1")?.scheme, "https")
    }

    func testHTTPSIsLeftAlone() {
        XCTAssertEqual(EndpointURL.normalise("https://status.example.com")?.scheme, "https")
    }
}
