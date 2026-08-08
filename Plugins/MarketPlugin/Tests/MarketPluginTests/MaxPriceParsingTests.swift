import Foundation
@testable import MarketPlugin
import XCTest

/// `parseMaxPrice` is a pure function specifically so this can test the
/// parsing without going through `MarketPanelView`.
final class MaxPriceParsingTests: XCTestCase {
    func testAnEmptyFieldMeansNoCap() {
        XCTAssertEqual(parseMaxPrice(""), .empty)
    }

    func testWhitespaceOnlyMeansNoCap() {
        XCTAssertEqual(parseMaxPrice("   "), .empty)
    }

    func testAPlainNumberParses() {
        XCTAssertEqual(parseMaxPrice("200"), .value(200))
    }

    func testADollarSignIsStripped() {
        XCTAssertEqual(parseMaxPrice("$200"), .value(200))
    }

    func testAThousandsCommaIsStripped() {
        XCTAssertEqual(parseMaxPrice("1,200"), .value(1200))
    }

    func testADollarSignAndCommaTogetherAreStripped() {
        XCTAssertEqual(parseMaxPrice("$1,200"), .value(1200))
    }

    func testCentsAreTruncatedToWholeDollars() {
        // "$200.50" must not become the digit-smashed 20050 that stripping
        // the "." outright would produce.
        XCTAssertEqual(parseMaxPrice("200.50"), .value(200))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(parseMaxPrice("  200  "), .value(200))
    }

    func testLettersAloneAreInvalidRatherThanNoCap() {
        // A non-empty field that fails to parse must be rejected, never
        // silently read as "no cap" — that is an uncapped watch the user
        // never asked for.
        XCTAssertEqual(parseMaxPrice("abc"), .invalid)
    }

    func testPunctuationAloneIsInvalid() {
        XCTAssertEqual(parseMaxPrice("$"), .invalid)
    }

    func testMultipleDecimalPointsAreInvalid() {
        XCTAssertEqual(parseMaxPrice("12.34.56"), .invalid)
    }
}
