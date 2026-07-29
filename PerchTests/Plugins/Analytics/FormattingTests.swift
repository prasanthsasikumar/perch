import XCTest
@testable import AnalyticsPlugin

final class FormattingTests: XCTestCase {
    func testCompactAbbreviatesThousandsAndMillions() {
        XCTAssertEqual(Formatting.compact(1_234), "1.2K")
        XCTAssertEqual(Formatting.compact(1_500_000), "1.5M")
        XCTAssertEqual(Formatting.compact(999), "999")
        XCTAssertEqual(Formatting.compact(0), "0")
    }

    /// The boundary is the interesting part: 1000 abbreviates, 999 does not.
    func testCompactSwitchesUnitAtExactlyAThousand() {
        XCTAssertEqual(Formatting.compact(1_000), "1.0K")
        XCTAssertEqual(Formatting.compact(1_000_000), "1.0M")
    }

    func testCompactGroupsSmallNumbers() {
        // Locale-independent: whatever the separator is, the digits are these.
        XCTAssertEqual(Formatting.compact(512).filter(\.isNumber), "512")
    }

    func testCompactHandlesNegatives() {
        XCTAssertEqual(Formatting.compact(-2_500), "-2.5K")
    }

    func testRateReadsAsAPercentage() {
        XCTAssertEqual(Formatting.rate(0.4231), "42.3%")
    }

    func testDurationReadsAsMinutesAndSeconds() {
        XCTAssertEqual(Formatting.duration(95.4), "1:35")
        XCTAssertEqual(Formatting.duration(0), "0:00")
        XCTAssertEqual(Formatting.duration(-1), "—")
    }
}

final class PercentChangeTests: XCTestCase {
    func testSignedToOneDecimal() {
        XCTAssertEqual(PercentChange(current: 114, previous: 100).text, "+14.0%")
        XCTAssertEqual(PercentChange(current: 97, previous: 100).text, "-3.0%")
    }

    /// Both zero-baseline cases the Python script special-cases. Calling them
    /// both "+inf" would claim growth where nothing happened at all.
    func testZeroBaselineWithNoTrafficIsUndefined() {
        XCTAssertEqual(PercentChange(current: 0, previous: 0), .undefined)
        XCTAssertEqual(PercentChange(current: 0, previous: 0).text, "N/A")
        XCTAssertNil(PercentChange(current: 0, previous: 0).isUp)
    }

    func testZeroBaselineWithTrafficIsNew() {
        XCTAssertEqual(PercentChange(current: 42, previous: 0), .fromZero)
        XCTAssertEqual(PercentChange(current: 42, previous: 0).text, "new")
        XCTAssertEqual(PercentChange(current: 42, previous: 0).isUp, true)
    }

    func testDirectionDrivesTheArrow() {
        XCTAssertEqual(PercentChange(current: 2, previous: 1).isUp, true)
        XCTAssertEqual(PercentChange(current: 1, previous: 2).isUp, false)
        // Flat is neither up nor down, so it gets no arrow and no colour.
        XCTAssertNil(PercentChange(current: 1, previous: 1).isUp)
    }
}
