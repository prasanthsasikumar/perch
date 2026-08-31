@testable import BusyPlugin
import WebKit
import XCTest

/// Runs the real `busyness.js` against saved HTML in a real `WKWebView`.
///
/// This lives in the app-hosted suite rather than the package one because a
/// `WKWebView` needs an app. No network: every page is loaded from a string.
/// `busyness-live.html` is the widget as Google served it on 2026-08-31, with
/// tracking attributes stripped; the others are edits of it.
@MainActor
final class BusyScriptTests: XCTestCase {
    private func html(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: BusyScriptTests.self).url(forResource: name, withExtension: "html"),
            "fixture \(name).html is missing from the test bundle"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extract(from fixture: String) async throws -> ExtractedPage {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768))
        let loaded = expectation(description: "page loaded")
        let delegate = BusyLoadWatcher { loaded.fulfill() }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(try html(fixture), baseURL: URL(string: "https://www.google.com/"))
        await fulfillment(of: [loaded], timeout: 10)

        let script = try extractScriptSource()
        let result = try await webView.evaluateJavaScript(script)
        return try decodeExtractedPage(try XCTUnwrap(result as? String))
    }

    func testItFindsTheWidgetAndTheName() async throws {
        let page = try await extract(from: "busyness-live")

        XCTAssertTrue(page.found)
        XCTAssertFalse(page.hasConsentForm)
        XCTAssertEqual(page.reading.name, "Lion Gym Kesavadasapuram")
    }

    func testItReadsTheLiveLine() async throws {
        let page = try await extract(from: "busyness-live")

        XCTAssertTrue(page.reading.isLive)
        XCTAssertEqual(page.reading.statusText, "A little busy")
        XCTAssertEqual(page.reading.day, 1)
    }

    func testItReadsTheCurrentHoursTwoBars() async throws {
        let page = try await extract(from: "busyness-live")

        XCTAssertEqual(page.reading.currentHour, 16)
        XCTAssertEqual(page.reading.usualPercent, 61)
        XCTAssertEqual(page.reading.livePercent, 78)
    }

    func testItReadsEveryHour() async throws {
        let page = try await extract(from: "busyness-live")
        let hours = page.reading.hours

        XCTAssertEqual(hours.count, 18)
        XCTAssertEqual(hours.first, HourBusyness(hour: 4, percent: 0))
        XCTAssertEqual(hours[1], HourBusyness(hour: 5, percent: 32))
        // The current hour's histogram entry is the usual bar, not the live one.
        XCTAssertEqual(hours.first { $0.hour == 16 }, HourBusyness(hour: 16, percent: 61))
        XCTAssertEqual(hours.first { $0.hour == 19 }, HourBusyness(hour: 19, percent: 98))
        XCTAssertEqual(hours.last, HourBusyness(hour: 21, percent: 60))
    }

    func testAWidgetWithNoLiveDataReportsTheUsualLine() async throws {
        let page = try await extract(from: "busyness-usual")

        XCTAssertTrue(page.found)
        XCTAssertFalse(page.reading.isLive)
        XCTAssertEqual(page.reading.statusText, "Usually a little busy")
        XCTAssertNil(page.reading.livePercent)
        XCTAssertEqual(page.reading.usualPercent, 61)
        XCTAssertEqual(page.reading.currentHour, 16)
    }

    func testAPageWithNoWidgetIsNotFound() async throws {
        let page = try await extract(from: "busyness-none")

        XCTAssertFalse(page.found)
        XCTAssertFalse(page.hasConsentForm)
        XCTAssertTrue(page.reading.hours.isEmpty)
    }

    func testAConsentPageIsFlagged() async throws {
        let page = try await extract(from: "busyness-consent")

        XCTAssertFalse(page.found)
        XCTAssertTrue(page.hasConsentForm)
    }
}

private final class BusyLoadWatcher: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
