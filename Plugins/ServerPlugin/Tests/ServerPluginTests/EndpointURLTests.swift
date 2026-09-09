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
