@testable import ServerPlugin
import XCTest

final class FormattingTests: XCTestCase {
    func testBytesUsesBinaryUnits() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(512), "512 B")
        XCTAssertEqual(Format.bytes(1024), "1.0 KB")
        XCTAssertEqual(Format.bytes(1536), "1.5 KB")
        XCTAssertEqual(Format.bytes(1_073_741_824), "1.0 GB")
    }

    /// A decimal earns its place below ten and nowhere else.
    func testBytesDropsTheDecimalOnceItStopsCarryingInformation() {
        XCTAssertEqual(Format.bytes(9.5 * 1024 * 1024), "9.5 MB")
        XCTAssertEqual(Format.bytes(938 * 1024 * 1024), "938 MB")
    }

    func testRateAppendsPerSecond() {
        XCTAssertEqual(Format.rate(2048), "2.0 KB/s")
    }

    func testUptimeShowsTheTwoLargestUnits() {
        XCTAssertEqual(Format.uptime(90), "1m")
        XCTAssertEqual(Format.uptime(3600 * 4 + 720), "4h 12m")
        XCTAssertEqual(Format.uptime(86_400 * 6 + 3600 * 4), "6d 4h")
    }

    /// Division by a zero total is the ordinary case for a box with no swap,
    /// and NaN must never reach a bar width or a label.
    func testNonFiniteInputIsSurvivable() {
        XCTAssertEqual(Format.percent(.nan), "0%")
        XCTAssertEqual(Format.load(.infinity), "0.00")
        XCTAssertEqual(Format.bytes(.nan), "0 B")
        XCTAssertEqual(Format.uptime(.nan), "unknown")
    }
}
