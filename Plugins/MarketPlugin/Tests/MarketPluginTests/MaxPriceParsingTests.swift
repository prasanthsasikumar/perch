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

    // MARK: - Trapping conversion (Critical fix)

    func testAValueBeyondIntMaxIsInvalidRatherThanTrapping() {
        // `Int(_: Double)` traps for anything at or beyond `Int.max` — a
        // trap here takes down the whole host, not just Market, and isn't a
        // clean exit, so `willTerminate` never fires either. This must
        // return `.invalid`, not crash the process.
        XCTAssertEqual(parseMaxPrice("9999999999999999999"), .invalid)
    }

    func testATwentyDigitValueIsInvalidRatherThanTrapping() {
        XCTAssertEqual(parseMaxPrice("99999999999999999999"), .invalid)
    }

    // MARK: - Sign and non-positive values

    func testANegativeValueIsInvalidRatherThanHavingItsSignStripped() {
        // The "-" is a sign, not a currency symbol — if it were filtered
        // out like "$" or "," is, "-5" would silently become a cap of 5.
        XCTAssertEqual(parseMaxPrice("-5"), .invalid)
    }

    func testZeroIsInvalid() {
        // A cap of $0 can never match anything — a watch that can never
        // find results is a mistake worth rejecting, not creating.
        XCTAssertEqual(parseMaxPrice("0"), .invalid)
    }

    func testAValueThatTruncatesToZeroIsInvalid() {
        // "0.4" truncates to 0 dollars, which is exactly as unmatchable as
        // a literal "0" — checked on the truncated value, not the
        // pre-truncation double, or this would slip through.
        XCTAssertEqual(parseMaxPrice("0.4"), .invalid)
    }
}
