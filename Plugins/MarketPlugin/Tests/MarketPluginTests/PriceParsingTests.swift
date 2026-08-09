@testable import MarketPlugin
import XCTest

final class PriceParsingTests: XCTestCase {
    func testAPlainDollarAmount() {
        XCTAssertEqual(parsePriceValue("$180"), 180)
    }

    func testAThousandsSeparator() {
        XCTAssertEqual(parsePriceValue("$1,200"), 1200)
    }

    func testCentsAreTruncated() {
        XCTAssertEqual(parsePriceValue("$199.99"), 199)
    }

    func testNoCurrencySymbol() {
        XCTAssertEqual(parsePriceValue("250"), 250)
    }

    func testANonNumericPriceHasNoValue() {
        // Facebook shows this for give-aways.
        XCTAssertNil(parsePriceValue("Free"))
    }

    func testAnEmptyStringHasNoValue() {
        XCTAssertNil(parsePriceValue(""))
    }

    func testSurroundingTextIsIgnored() {
        XCTAssertEqual(parsePriceValue("$45 · Auckland"), 45)
    }

    func testAnAbsurdlyLargeNumberHasNoValue() {
        // Must not trap. Int(String) returns nil on overflow, where
        // Int(Double) would trap — which is exactly how an earlier version
        // of the panel's price field crashed the whole app.
        XCTAssertNil(parsePriceValue("$99999999999999999999"))
    }
}
