@testable import ServerPlugin
import XCTest

/// Every URLError used to collapse into "Couldn't reach", which hid an App
/// Transport Security rejection behind a message that blamed the network.
final class ServerErrorMappingTests: XCTestCase {
    private func map(_ code: URLError.Code) -> ServerError {
        ServerError.from(URLError(code), host: "box.example.com")
    }

    func testBlockedCleartextIsNamedAsSuch() {
        XCTAssertEqual(map(.appTransportSecurityRequiresSecureConnection),
                       .insecureBlocked("box.example.com"))
        XCTAssertTrue(map(.appTransportSecurityRequiresSecureConnection).message.contains("https"))
    }

    func testTimeoutIsDistinctFromUnreachable() {
        XCTAssertEqual(map(.timedOut), .timedOut("box.example.com"))
        XCTAssertNotEqual(map(.timedOut), .unreachable("box.example.com"))
    }

    func testCertificateProblemsReadAsTLSFailures() {
        for code in [URLError.Code.secureConnectionFailed, .serverCertificateUntrusted,
                     .serverCertificateHasBadDate, .serverCertificateNotYetValid] {
            XCTAssertEqual(map(code), .tlsFailed("box.example.com"), "\(code)")
        }
    }

    /// An unrecognised code must not be dressed up as a specific diagnosis.
    func testUnknownCodesStayUnreachable() {
        XCTAssertEqual(map(.cannotFindHost), .unreachable("box.example.com"))
        XCTAssertEqual(map(.networkConnectionLost), .unreachable("box.example.com"))
    }

    func testEveryMessageEndsAsASentence() {
        let all: [ServerError] = [.unauthorized, .unreachable("h"), .timedOut("h"),
                                  .insecureBlocked("h"), .tlsFailed("h"),
                                  .badStatus(500), .notAnAgent, .badURL]
        for e in all { XCTAssertTrue(e.message.hasSuffix("."), e.message) }
    }
}
