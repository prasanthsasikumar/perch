@testable import MarketPlugin
import WebKit
import XCTest

/// Runs the real `extract.js` against saved HTML in a real `WKWebView`.
///
/// This lives in the app-hosted suite rather than the package one because a
/// `WKWebView` needs an app. No network: every page is loaded from a string.
@MainActor
final class ExtractScriptTests: XCTestCase {
    private func html(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: ExtractScriptTests.self)
                .url(forResource: name, withExtension: "html"),
            "fixture \(name).html is missing from the test bundle"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Loads HTML, runs extract.js, and returns whatever it produced.
    private func extract(from fixture: String) async throws -> [ScrapedListing] {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768))
        let loaded = expectation(description: "page loaded")
        let delegate = LoadWatcher { loaded.fulfill() }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            try html(fixture), baseURL: URL(string: "https://www.facebook.com/")
        )
        await fulfillment(of: [loaded], timeout: 10)

        let script = try extractScriptSource()
        let result = try await webView.evaluateJavaScript(script)
        return try decodeExtractedListings(try XCTUnwrap(result as? String))
    }

    func testItFindsEveryListing() async throws {
        let listings = try await extract(from: "marketplace-results")

        XCTAssertEqual(listings.map(\.id), ["1001", "1002", "1003"])
    }

    func testItReadsTheFields() async throws {
        let listings = try await extract(from: "marketplace-results")
        let gopro = try XCTUnwrap(listings.first { $0.id == "1001" })

        XCTAssertEqual(gopro.title, "GoPro Hero 12")
        XCTAssertEqual(gopro.price, "$180")
        XCTAssertEqual(gopro.priceValue, 180)
        XCTAssertEqual(gopro.location, "Auckland")
        XCTAssertEqual(gopro.url.absoluteString,
                       "https://www.facebook.com/marketplace/item/1001")
    }

    func testAThousandsSeparatedPriceSurvives() async throws {
        let listings = try await extract(from: "marketplace-results")
        let macbook = try XCTUnwrap(listings.first { $0.id == "1002" })

        XCTAssertEqual(macbook.priceValue, 1200)
    }

    func testAFreeListingHasNoNumericPrice() async throws {
        let listings = try await extract(from: "marketplace-results")
        let boxes = try XCTUnwrap(listings.first { $0.id == "1003" })

        XCTAssertEqual(boxes.price, "Free")
        XCTAssertNil(boxes.priceValue)
    }

    func testARepeatedListingAppearsOnce() async throws {
        let listings = try await extract(from: "marketplace-results")

        XCTAssertEqual(listings.filter { $0.id == "1001" }.count, 1)
    }

    func testNonListingLinksAreIgnored() async throws {
        let listings = try await extract(from: "marketplace-results")

        XCTAssertFalse(listings.contains { $0.title == "Electronics" })
    }

    // MARK: - Facebook's 2026-08 card markup

    func testItReadsTheRowsOfACurrentCard() async throws {
        let listings = try await extract(from: "marketplace-mixed")
        let bike = try XCTUnwrap(listings.first { $0.id == "5001" })

        XCTAssertEqual(bike.title, "Interceptor 650")
        XCTAssertEqual(bike.price, "₹276,000")
        XCTAssertEqual(bike.priceValue, 276_000)
        XCTAssertEqual(bike.location, "Kochi, KL")
        XCTAssertEqual(bike.imageURL?.absoluteString, "https://img.example/5001.jpg")
    }

    func testAnUntitledCardKeepsItsLocationOutOfTheTitle() async throws {
        let listings = try await extract(from: "marketplace-mixed")
        let untitled = try XCTUnwrap(listings.first { $0.id == "5002" })

        XCTAssertEqual(untitled.title, "")
        XCTAssertEqual(untitled.location, "Palakkad, KL")
        // The struck-through earlier price is not the price.
        XCTAssertEqual(untitled.price, "₹250,000")
    }

    func testListingsAfterTheOutsideYourSearchLineAreNotResults() async throws {
        let listings = try await extract(from: "marketplace-mixed")

        XCTAssertEqual(listings.map(\.id), ["5001", "5002"])
    }

    func testANoResultsPageYieldsNothingDespiteThePadding() async throws {
        let listings = try await extract(from: "marketplace-outside")

        XCTAssertTrue(listings.isEmpty)
    }

    func testAnEmptyResultsPageYieldsNothing() async throws {
        // Bound to a local first: XCTAssert takes an autoclosure, which
        // cannot contain an `await`.
        let listings = try await extract(from: "marketplace-empty")

        XCTAssertTrue(listings.isEmpty)
    }

    func testALoginPageYieldsNothing() async throws {
        // It must not throw, and it must not invent listings. The decision
        // that this IS a login wall belongs to LoginSignals, not here.
        let listings = try await extract(from: "marketplace-login")

        XCTAssertTrue(listings.isEmpty)
    }
}

/// Minimal navigation delegate: fires once the page has finished loading.
private final class LoadWatcher: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
