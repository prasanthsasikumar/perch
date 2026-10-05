@testable import BusyPlugin
import WebKit
import XCTest

/// Runs the real `planetfitness.js` against a saved club page in a real
/// `WKWebView`. `planetfitness-club.html` is the Philadelphia (Washington Ave)
/// page as planetfitness.com rendered it on 2026-10-05 at 08:34 local time,
/// with external scripts and resources stripped and its public API keys
/// redacted. No network.
@MainActor
final class PlanetFitnessScriptTests: XCTestCase {
    private func extract(_ html: String) async throws -> ExtractedPage {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 900))
        let loaded = expectation(description: "page loaded")
        let delegate = BusyLoadWatcher { loaded.fulfill() }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.planetfitness.com/"))
        await fulfillment(of: [loaded], timeout: 30)
        let result = try await webView.evaluateJavaScript(try extractScriptSource(named: "planetfitness"))
        return try decodeExtractedPage(try XCTUnwrap(result as? String))
    }

    private func clubPage() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "planetfitness-club", withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testItReadsTheMeterAndTheName() async throws {
        let page = try await extract(try clubPage())
        XCTAssertTrue(page.found)
        XCTAssertTrue(page.reading.isLive)
        XCTAssertEqual(page.reading.livePercent, 11)
        XCTAssertEqual(page.reading.name, "Planet Fitness Philadelphia (Washington Ave)")
    }

    func testItDecodesTheHeadcount() async throws {
        let page = try await extract(try clubPage())
        XCTAssertEqual(page.reading.headcount, 38)
        XCTAssertEqual(page.reading.capacity, 334)
    }

    func testItReadsTodaysCrowdHistory() async throws {
        let page = try await extract(try clubPage())
        XCTAssertEqual(page.reading.day, 1, "Monday's tab is selected")
        XCTAssertEqual(page.reading.hours.count, 24)
        XCTAssertEqual(page.reading.hours.first { $0.hour == 6 }?.percent, 16)
        XCTAssertEqual(page.reading.hours.first { $0.hour == 5 }?.percent, 9)
    }

    func testAPageWithoutTheMeterIsNotFound() async throws {
        let page = try await extract("<html><head><title>Gym in Nowhere, XX | Planet Fitness</title></head><body>Closed</body></html>")
        XCTAssertFalse(page.found)
        XCTAssertNil(page.reading.headcount)
    }
}
