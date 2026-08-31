@testable import BusyPlugin
import XCTest

final class ExtractedBusynessTests: XCTestCase {
    func testDecodesAFullPage() throws {
        let json = """
        {"found":true,"hasConsentForm":false,"name":"Lion Gym","statusText":"A little busy",
         "isLive":true,"livePercent":78,"usualPercent":61,"currentHour":16,"day":1,
         "hours":[{"hour":15,"percent":50},{"hour":16,"percent":61}]}
        """

        let page = try decodeExtractedPage(json)

        XCTAssertTrue(page.found)
        XCTAssertFalse(page.hasConsentForm)
        XCTAssertEqual(page.reading.name, "Lion Gym")
        XCTAssertEqual(page.reading.statusText, "A little busy")
        XCTAssertTrue(page.reading.isLive)
        XCTAssertEqual(page.reading.livePercent, 78)
        XCTAssertEqual(page.reading.usualPercent, 61)
        XCTAssertEqual(page.reading.currentHour, 16)
        XCTAssertEqual(page.reading.day, 1)
        XCTAssertEqual(page.reading.hours, [
            HourBusyness(hour: 15, percent: 50), HourBusyness(hour: 16, percent: 61),
        ])
    }

    func testAPageWithNoWidgetDecodesAsNotFound() throws {
        let json = """
        {"found":false,"hasConsentForm":false,"name":null,"statusText":null,"isLive":false,
         "livePercent":null,"usualPercent":null,"currentHour":null,"day":null,"hours":[]}
        """

        let page = try decodeExtractedPage(json)

        XCTAssertFalse(page.found)
        XCTAssertNil(page.reading.name)
        XCTAssertTrue(page.reading.hours.isEmpty)
    }

    func testGarbageIsAnError() {
        XCTAssertThrowsError(try decodeExtractedPage("not json"))
        XCTAssertThrowsError(try decodeExtractedPage("[]"))
    }

    func testTheSearchURLPinsEnglish() throws {
        let url = try XCTUnwrap(googleSearchURL(query: "lion gym kesavadasapuram"))

        XCTAssertEqual(
            url.absoluteString,
            "https://www.google.com/search?q=lion%20gym%20kesavadasapuram&hl=en"
        )
    }

    func testABlankQueryHasNoURL() {
        XCTAssertNil(googleSearchURL(query: "   "))
    }
}

@MainActor
final class GoogleBusynessSourceJudgeTests: XCTestCase {
    private let source = GoogleBusynessSource(session: GoogleSession())

    private func page(_ payload: String, at url: String = "https://www.google.com/search?q=x") -> LoadedPage {
        LoadedPage(payload: payload, finalURL: URL(string: url))
    }

    private let found = """
    {"found":true,"hasConsentForm":false,"name":"X","statusText":null,"isLive":false,
     "livePercent":null,"usualPercent":null,"currentHour":null,"day":null,"hours":[]}
    """
    private let missing = """
    {"found":false,"hasConsentForm":false,"name":null,"statusText":null,"isLive":false,
     "livePercent":null,"usualPercent":null,"currentHour":null,"day":null,"hours":[]}
    """

    func testAWidgetIsAReading() throws {
        XCTAssertEqual(try source.judge(page(found)).name, "X")
    }

    func testNoWidgetIsNotFound() {
        XCTAssertThrowsError(try source.judge(page(missing))) { error in
            XCTAssertEqual(error as? BusyError, .notFound)
        }
    }

    func testAConsentRedirectIsAConsentWallEvenWithoutAForm() {
        XCTAssertThrowsError(
            try source.judge(page(missing, at: "https://consent.google.com/m?continue=x"))
        ) { error in
            XCTAssertEqual(error as? BusyError, .consentWall)
        }
    }

    func testAConsentFormIsAConsentWall() {
        let consent = missing.replacingOccurrences(of: "\"hasConsentForm\":false", with: "\"hasConsentForm\":true")
        XCTAssertThrowsError(try source.judge(page(consent))) { error in
            XCTAssertEqual(error as? BusyError, .consentWall)
        }
    }
}
