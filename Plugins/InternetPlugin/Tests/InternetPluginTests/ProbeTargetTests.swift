@testable import InternetPlugin
import XCTest

final class ProbeTargetTests: XCTestCase {
    private func target(_ id: String) -> ProbeTarget {
        ProbeTarget.defaults.first { $0.id == id }!
    }

    func testExactlyOneTargetSkipsDNS() {
        XCTAssertEqual(ProbeTarget.defaults.filter { !$0.usesDNS }.count, 1)
    }

    func testGoogleWantsA204() {
        XCTAssertTrue(target("google").accepts(status: 204, body: Data()))
        // A portal answering with its login page is a 200.
        XCTAssertFalse(target("google").accepts(status: 200, body: Data("<html>".utf8)))
    }

    func testAppleWantsItsSuccessPage() {
        let success = Data("<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>".utf8)
        XCTAssertTrue(target("apple").accepts(status: 200, body: success))
        XCTAssertFalse(target("apple").accepts(status: 200, body: Data("Please log in".utf8)))
        XCTAssertFalse(target("apple").accepts(status: 302, body: success))
    }

    func testOutcomeCodableRoundTrip() throws {
        let check = makeCheck(at: Date(timeIntervalSince1970: 0), overrides: [
            "google": .dnsFailed, "apple": .intercepted, "cloudflare": .ok(milliseconds: 12.5),
        ])
        let decoded = try JSONDecoder().decode(Check.self, from: JSONEncoder().encode(check))
        XCTAssertEqual(decoded, check)
    }

    func testTrendMarksFailuresAndKeepsAFloor() {
        let points = LatencyGeometry.normalise([10, nil, 50])
        XCTAssertEqual(points.map(\.x), [0, 0.5, 1])
        XCTAssertEqual(points[0].y, 0.9)
        XCTAssertNil(points[1].y)
        XCTAssertEqual(points[2].y, 0.5)
        XCTAssertEqual(LatencyGeometry.normalise([400, 200])[1].y, 0.5)
    }

    func testFormatting() {
        XCTAssertEqual(Format.milliseconds(19.6), "20 ms")
        XCTAssertEqual(Format.speed(312.4), "312 Mbps")
        XCTAssertEqual(Format.speed(2.44), "2.4 Mbps")
    }
}
