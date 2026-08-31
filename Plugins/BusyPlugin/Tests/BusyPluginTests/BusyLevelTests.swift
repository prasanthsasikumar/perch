@testable import BusyPlugin
import XCTest

final class BusyLevelTests: XCTestCase {
    func testGooglesWordingWins() {
        XCTAssertEqual(BusyLevel.from(statusText: "Not busy", percent: 95), .quiet)
        XCTAssertEqual(BusyLevel.from(statusText: "Not too busy", percent: 95), .quiet)
        XCTAssertEqual(BusyLevel.from(statusText: "A little busy", percent: 95), .moderate)
        XCTAssertEqual(BusyLevel.from(statusText: "Usually a little busy", percent: nil), .moderate)
        XCTAssertEqual(BusyLevel.from(statusText: "Busy", percent: 10), .busy)
        XCTAssertEqual(BusyLevel.from(statusText: "Very busy", percent: 10), .busy)
        XCTAssertEqual(BusyLevel.from(statusText: "As busy as it gets", percent: 10), .busy)
    }

    func testThePercentageStandsInForUnknownWording() {
        XCTAssertEqual(BusyLevel.from(statusText: nil, percent: 20), .quiet)
        XCTAssertEqual(BusyLevel.from(statusText: nil, percent: 55), .moderate)
        XCTAssertEqual(BusyLevel.from(statusText: nil, percent: 90), .busy)
        XCTAssertEqual(BusyLevel.from(statusText: "Bustling", percent: 90), .busy)
    }

    func testNothingIsUnknown() {
        XCTAssertEqual(BusyLevel.from(statusText: nil, percent: nil), .unknown)
    }

    func testALiveReadingUsesTheLiveFigure() {
        let reading = BusyReading(statusText: nil, isLive: true, livePercent: 90, usualPercent: 10)
        XCTAssertEqual(reading.level, .busy)
    }

    func testAUsualReadingUsesTheUsualFigure() {
        let reading = BusyReading(statusText: nil, isLive: false, livePercent: nil, usualPercent: 10)
        XCTAssertEqual(reading.level, .quiet)
    }
}

final class BusyReadingSummaryTests: XCTestCase {
    func testLiveWithBothFigures() {
        let reading = BusyReading(statusText: "A little busy", isLive: true, livePercent: 78, usualPercent: 61)
        XCTAssertEqual(reading.summary, "A little busy · 78% now, usually 61%")
    }

    func testLiveWithNoUsualFigure() {
        let reading = BusyReading(statusText: "Busy", isLive: true, livePercent: 90)
        XCTAssertEqual(reading.summary, "Busy · 90% now")
    }

    func testLiveWordsOnly() {
        XCTAssertEqual(BusyReading(statusText: "Not busy", isLive: true).summary, "Not busy")
    }

    func testUsualWording() {
        XCTAssertEqual(BusyReading(statusText: "Usually not too busy").summary, "Usually not too busy")
    }

    func testUsualFigureOnly() {
        XCTAssertEqual(BusyReading(usualPercent: 40).summary, "Usually 40% at this hour")
    }

    func testNothing() {
        XCTAssertEqual(BusyReading().summary, "No busyness data")
    }
}
