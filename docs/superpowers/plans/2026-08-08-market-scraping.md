# Market Scraping Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Market tab find real listings — a `WKWebView`-backed `ListingSource`, DOM extraction, positive login detection, and a sign-in window whose cookies survive restarts.

**Architecture:** One `WKWebView` on the shared cookie store, owned by `FacebookSession`, parked offscreen while polling and brought on screen to sign in. Everything decidable without a browser is split out into pure functions — price parsing, login judgement, URL building, JSON decoding — so the untestable surface is as small as it can be.

**Tech Stack:** Swift 5.9, macOS 14, WebKit, SwiftUI, Observation, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-08-market-scraping-design.md`

## Global Constraints

- macOS 14, `swift-tools-version: 5.9`. Swift 6.0-only APIs do not compile — `Array.count(where:)`, for one.
- No new dependencies, Swift or JavaScript. No bundler, no framework.
- Do not modify `PerchKit`.
- `Perch.xcodeproj` is gitignored; only `project.yml` is tracked. Run `xcodegen generate` after editing it.
- Perch already has `com.apple.security.network.client`; `WKWebView` needs no new entitlement. **Do not add entitlements.**
- Poll policy is unchanged and is not a tuning preference: serial, 600s floor, ±20% jitter, backoff capped at 7200s.
- **No test may hit the network or require a login.** Fixture tests load saved HTML with `loadHTMLString`. If a test would need real Facebook, it does not get written — say so in the report instead.
- **Do not automate the app's UI.** No accessibility scripting, no `cliclick`, no coordinate clicks — this runs on the user's real desktop and a previous agent's stray click hit unrelated content. Building and launching the app is fine; clicking through it is the user's job.

## Where tests live

Two suites, and the split matters:

- **Package tests** — `Plugins/MarketPlugin/Tests/MarketPluginTests/`, run with
  `swift test --package-path Plugins/MarketPlugin`. Under a second. Everything pure goes here.
- **App-hosted tests** — `PerchTests/Plugins/Market/`, run with
  `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -25`. About a minute. **Only** the `extract.js` fixture tests go here, because they need a real `WKWebView` and therefore a real app host.

Run both **in the foreground**. Backgrounding test commands has stranded three agents on this project.

## The honest limit on fixtures

A real Facebook fixture needs a logged-in session, which belongs to the user. The fixtures in Task 3 are hand-built from the structure Facebook currently uses: they prove the parser's logic, not that it matches today's Facebook. **Do not claim otherwise in any report.** After sign-in works the user will save a real results page and the fixtures get replaced; until then the live run is the only proof.

---

### Task 1: Numeric price on `ScrapedListing`

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/PriceParsing.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Store/NewListings.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/PriceParsingTests.swift`

**Interfaces:**
- Produces: `parsePriceValue(_ display: String) -> Int?`, and `ScrapedListing` gains `priceValue: Int?` as the last initializer parameter with a default of `nil`.

- [ ] **Step 1: Write the failing test**

`Tests/MarketPluginTests/PriceParsingTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter PriceParsingTests`
Expected: FAIL — `cannot find 'parsePriceValue' in scope`

- [ ] **Step 3: Write the implementation**

`Sources/MarketPlugin/Session/PriceParsing.swift`:

```swift
import Foundation

/// The numeric value behind a displayed price, in whole units of currency.
///
/// The display string is what Facebook rendered — "$180", "Free", "$1,200".
/// A client cannot sort or threshold on that, so this pulls out the number
/// when there is one and returns `nil` when there is not.
///
/// Cents are truncated rather than rounded: a cap of $200 should not be
/// satisfied by $200.99.
public func parsePriceValue(_ display: String) -> Int? {
    var digits = ""
    var sawSeparator = false
    for character in display {
        if character.isNumber {
            if sawSeparator { break }  // stop at the cents
            digits.append(character)
        } else if character == "." && !digits.isEmpty {
            sawSeparator = true
        } else if character == "," {
            continue  // thousands separator
        } else if !digits.isEmpty {
            break  // the number ended; ignore any trailing text
        }
    }
    guard !digits.isEmpty else { return nil }
    // `Int(digits)` returns nil rather than trapping when it overflows, which
    // is what we want for absurd input.
    return Int(digits)
}
```

- [ ] **Step 4: Add the field to `ScrapedListing`**

In `Store/NewListings.swift`, add the stored property after `imageURL`:

```swift
    /// The numeric price, when the display string contained one. `nil` for
    /// "Free" and anything else unparseable.
    public let priceValue: Int?
```

and the initializer parameter last, defaulted so existing call sites keep
compiling:

```swift
        imageURL: URL?,
        priceValue: Int? = nil
    ) {
        ...
        self.imageURL = imageURL
        self.priceValue = priceValue
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 100 tests, 0 failures (92 existing plus 8 new)

- [ ] **Step 6: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: numeric price alongside the display string"
```

---

### Task 2: Login detection as a pure decision

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/LoginSignals.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/LoginSignalsTests.swift`

**Interfaces:**
- Produces: `struct LoginSignals(urlPath: String, hasPasswordField: Bool, hasLoginForm: Bool, listingCount: Int)` and `func isLoginWall(_ signals: LoginSignals) -> Bool`.

- [ ] **Step 1: Write the failing test**

`Tests/MarketPluginTests/LoginSignalsTests.swift`:

```swift
@testable import MarketPlugin
import XCTest

final class LoginSignalsTests: XCTestCase {
    private func signals(
        path: String = "/marketplace/auckland/search",
        password: Bool = false,
        form: Bool = false,
        listings: Int = 0
    ) -> LoginSignals {
        LoginSignals(
            urlPath: path,
            hasPasswordField: password,
            hasLoginForm: form,
            listingCount: listings
        )
    }

    func testARedirectToLoginIsAWall() {
        XCTAssertTrue(isLoginWall(signals(path: "/login/device-based/regular/login/")))
    }

    func testALoginPathAnywhereIsAWall() {
        XCTAssertTrue(isLoginWall(signals(path: "/login.php")))
    }

    func testAPasswordFieldIsAWall() {
        XCTAssertTrue(isLoginWall(signals(password: true)))
    }

    func testALoginFormIsAWall() {
        XCTAssertTrue(isLoginWall(signals(form: true)))
    }

    func testAnEmptyResultsPageIsNotAWall() {
        // The whole point: "nothing matched" must never be read as "logged
        // out". Conflating them is what made the sign-in prompt unreachable
        // in the superseded Python implementation.
        XCTAssertFalse(isLoginWall(signals(listings: 0)))
    }

    func testAPageWithListingsIsNotAWall() {
        XCTAssertFalse(isLoginWall(signals(listings: 12)))
    }

    func testListingsWinOverAStrayPasswordField() {
        // Facebook renders a hidden login form on some logged-in pages. If we
        // got listings, we are demonstrably logged in.
        XCTAssertFalse(isLoginWall(signals(password: true, listings: 12)))
    }

    func testAMarketplacePathWithNoSignalsIsNotAWall() {
        XCTAssertFalse(isLoginWall(signals()))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter LoginSignalsTests`
Expected: FAIL — `cannot find 'LoginSignals' in scope`

- [ ] **Step 3: Write the implementation**

`Sources/MarketPlugin/Session/LoginSignals.swift`:

```swift
import Foundation

/// What the page looked like after a search navigation.
///
/// Gathered by `FacebookSession` from the live webview; judged here, so the
/// judgement is testable without a browser.
public struct LoginSignals: Equatable, Sendable {
    public let urlPath: String
    public let hasPasswordField: Bool
    public let hasLoginForm: Bool
    public let listingCount: Int

    public init(urlPath: String, hasPasswordField: Bool, hasLoginForm: Bool, listingCount: Int) {
        self.urlPath = urlPath
        self.hasPasswordField = hasPasswordField
        self.hasLoginForm = hasLoginForm
        self.listingCount = listingCount
    }
}

/// Whether the page we landed on is a login wall.
///
/// Detection is positive: it looks for evidence of a login screen, and never
/// infers one from an empty result set. That inference is exactly what broke
/// the superseded Python implementation — upstream returned an empty list for
/// both "no matches" and "session dead", so the sign-in state could never fire
/// and a dead session looked like a quiet search forever.
public func isLoginWall(_ signals: LoginSignals) -> Bool {
    // Anything rendered means we are through. Facebook leaves login markup in
    // the DOM of some signed-in pages, so listings outrank those markers.
    guard signals.listingCount == 0 else { return false }
    if signals.urlPath.contains("/login") { return true }
    return signals.hasPasswordField || signals.hasLoginForm
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 108 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: positive login-wall detection"
```

---

### Task 3: `extract.js` and its fixtures

The one task whose correctness cannot be proved without a browser. The JS→JSON step gets a fixture test in the app-hosted suite; the JSON→Swift step is split out as a pure function so it is package-testable.

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/Resources/extract.js`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/ExtractedListings.swift`
- Modify: `Plugins/MarketPlugin/Package.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/ExtractedListingsTests.swift`
- Test: `PerchTests/Plugins/Market/ExtractScriptTests.swift`
- Create: `PerchTests/Plugins/Market/Fixtures/marketplace-results.html`
- Create: `PerchTests/Plugins/Market/Fixtures/marketplace-empty.html`
- Create: `PerchTests/Plugins/Market/Fixtures/marketplace-login.html`

**Interfaces:**
- Consumes: `ScrapedListing`, `parsePriceValue`.
- Produces: `extractScriptSource() throws -> String` loading the bundled JS; `decodeExtractedListings(_ json: String) throws -> [ScrapedListing]`; `enum ExtractionError: Error { case scriptMissing, malformedPayload }`.

- [ ] **Step 1: Declare the resource**

In `Plugins/MarketPlugin/Package.swift`, give the target its resources:

```swift
        .target(
            name: "MarketPlugin",
            dependencies: ["PerchKit"],
            resources: [.process("Session/Resources")]
        ),
```

- [ ] **Step 2: Write the failing decoder test**

`Tests/MarketPluginTests/ExtractedListingsTests.swift`:

```swift
@testable import MarketPlugin
import XCTest

final class ExtractedListingsTests: XCTestCase {
    func testDecodesAListing() throws {
        let json = """
        [{"id":"123","title":"GoPro Hero 12","price":"$180",
          "location":"Auckland","url":"https://www.facebook.com/marketplace/item/123",
          "imageURL":"https://img.example/1.jpg"}]
        """

        let listings = try decodeExtractedListings(json)

        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings[0].id, "123")
        XCTAssertEqual(listings[0].title, "GoPro Hero 12")
        XCTAssertEqual(listings[0].price, "$180")
        XCTAssertEqual(listings[0].priceValue, 180)
        XCTAssertEqual(listings[0].location, "Auckland")
    }

    func testAnEmptyArrayDecodesToNothing() throws {
        XCTAssertTrue(try decodeExtractedListings("[]").isEmpty)
    }

    func testAMissingImageIsAllowed() throws {
        let json = """
        [{"id":"1","title":"T","price":"$1","location":"L",
          "url":"https://www.facebook.com/marketplace/item/1","imageURL":null}]
        """

        XCTAssertNil(try decodeExtractedListings(json)[0].imageURL)
    }

    func testAnEntryWithAnUnusableURLIsSkippedRatherThanFailingTheBatch() throws {
        // One malformed row must not lose the whole poll.
        let json = """
        [{"id":"1","title":"T","price":"$1","location":"L","url":"not a url","imageURL":null},
         {"id":"2","title":"U","price":"$2","location":"L",
          "url":"https://www.facebook.com/marketplace/item/2","imageURL":null}]
        """

        XCTAssertEqual(try decodeExtractedListings(json).map(\.id), ["2"])
    }

    func testGarbageIsAnError() {
        XCTAssertThrowsError(try decodeExtractedListings("not json"))
    }

    func testAFreePriceDecodesWithNoNumericValue() throws {
        let json = """
        [{"id":"1","title":"T","price":"Free","location":"L",
          "url":"https://www.facebook.com/marketplace/item/1","imageURL":null}]
        """

        XCTAssertNil(try decodeExtractedListings(json)[0].priceValue)
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter ExtractedListingsTests`
Expected: FAIL — `cannot find 'decodeExtractedListings' in scope`

- [ ] **Step 4: Write the decoder**

`Sources/MarketPlugin/Session/ExtractedListings.swift`:

```swift
import Foundation

public enum ExtractionError: Error, Equatable {
    /// The bundled extract.js could not be found. A packaging problem, not a
    /// scraping one.
    case scriptMissing
    /// The script returned something that was not the expected JSON array.
    case malformedPayload
}

/// One row as `extract.js` emits it.
private struct RawListing: Decodable {
    let id: String
    let title: String
    let price: String
    let location: String
    let url: String
    let imageURL: String?
}

/// The JavaScript source that runs inside the webview.
///
/// Kept as a bundled resource rather than a Swift string literal so a selector
/// fix — which is the maintenance this design signs up for — is a one-file
/// change that does not touch compiled code.
public func extractScriptSource() throws -> String {
    guard let url = Bundle.module.url(forResource: "extract", withExtension: "js"),
          let source = try? String(contentsOf: url, encoding: .utf8)
    else { throw ExtractionError.scriptMissing }
    return source
}

/// Turns the script's JSON into listings.
///
/// A row with an unusable URL is skipped rather than failing the batch: one
/// malformed entry should cost one listing, not a whole poll.
public func decodeExtractedListings(_ json: String) throws -> [ScrapedListing] {
    guard let data = json.data(using: .utf8),
          let rows = try? JSONDecoder().decode([RawListing].self, from: data)
    else { throw ExtractionError.malformedPayload }

    return rows.compactMap { row in
        guard let url = URL(string: row.url), url.scheme == "https" else { return nil }
        return ScrapedListing(
            id: row.id,
            title: row.title,
            price: row.price,
            location: row.location,
            url: url,
            imageURL: row.imageURL.flatMap(URL.init(string:)),
            priceValue: parsePriceValue(row.price)
        )
    }
}
```

- [ ] **Step 5: Run the decoder tests**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 114 tests, 0 failures

- [ ] **Step 6: Write `extract.js`**

`Sources/MarketPlugin/Session/Resources/extract.js`:

```javascript
// Pulls listings out of a Facebook Marketplace search results page.
//
// Facebook's class names are obfuscated and change often, so this anchors on
// the one thing that is structural rather than cosmetic: every result links to
// /marketplace/item/<id>. Everything else is read from the anchor's own text,
// in the order Facebook renders it — price first, then title, then location.
//
// Returns a JSON string, because that is what evaluateJavaScript can hand back
// across the bridge without ceremony.
(function () {
  function textPieces(anchor) {
    // Visible, non-empty strings in document order, de-duplicated.
    var out = [];
    var walker = document.createTreeWalker(anchor, NodeFilter.SHOW_TEXT, null);
    var node;
    while ((node = walker.nextNode())) {
      var value = node.textContent.trim();
      if (value && out.indexOf(value) === -1) out.push(value);
    }
    return out;
  }

  function looksLikePrice(value) {
    return /^(free|\$|£|€|₹)/i.test(value) || /^[\d,]+(\.\d+)?$/.test(value);
  }

  var seen = {};
  var results = [];
  var anchors = document.querySelectorAll('a[href*="/marketplace/item/"]');

  for (var i = 0; i < anchors.length; i++) {
    var anchor = anchors[i];
    var match = anchor.getAttribute("href").match(/\/marketplace\/item\/(\d+)/);
    if (!match) continue;
    var id = match[1];
    if (seen[id]) continue;
    seen[id] = true;

    var pieces = textPieces(anchor);
    var price = "";
    var rest = [];
    for (var p = 0; p < pieces.length; p++) {
      if (!price && looksLikePrice(pieces[p])) price = pieces[p];
      else rest.push(pieces[p]);
    }

    var image = anchor.querySelector("img");

    results.push({
      id: id,
      title: rest.length > 0 ? rest[0] : "",
      price: price,
      location: rest.length > 1 ? rest[rest.length - 1] : "",
      url: "https://www.facebook.com/marketplace/item/" + id,
      imageURL: image ? image.getAttribute("src") : null,
    });
  }

  return JSON.stringify(results);
})();
```

- [ ] **Step 7: Write the fixtures**

These are hand-built from the structure Facebook currently uses. They prove the
parser's logic, not that it matches today's Facebook — see "The honest limit on
fixtures" above.

`PerchTests/Plugins/Market/Fixtures/marketplace-results.html`:

```html
<!doctype html>
<html><body>
  <div>
    <a href="/marketplace/item/1001/?ref=search">
      <img src="https://img.example/1001.jpg" />
      <span>$180</span><span>GoPro Hero 12</span><span>Auckland</span>
    </a>
    <a href="/marketplace/item/1002/?ref=search">
      <img src="https://img.example/1002.jpg" />
      <span>$1,200</span><span>MacBook Air M2</span><span>Hamilton</span>
    </a>
    <a href="/marketplace/item/1003/">
      <span>Free</span><span>Moving boxes</span><span>Manukau</span>
    </a>
    <!-- Facebook repeats results as you scroll; the same id must appear once. -->
    <a href="/marketplace/item/1001/?ref=scroll">
      <span>$180</span><span>GoPro Hero 12</span><span>Auckland</span>
    </a>
    <!-- Not a listing. Must be ignored. -->
    <a href="/marketplace/category/electronics">Electronics</a>
  </div>
</body></html>
```

`PerchTests/Plugins/Market/Fixtures/marketplace-empty.html`:

```html
<!doctype html>
<html><body>
  <div><span>No results found</span></div>
</body></html>
```

`PerchTests/Plugins/Market/Fixtures/marketplace-login.html`:

```html
<!doctype html>
<html><body>
  <form action="/login/device-based/regular/login/" method="post">
    <input type="text" name="email" />
    <input type="password" name="pass" />
    <button type="submit">Log In</button>
  </form>
</body></html>
```

- [ ] **Step 8: Write the failing fixture test**

`PerchTests/Plugins/Market/ExtractScriptTests.swift`:

```swift
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

    func testAnEmptyResultsPageYieldsNothing() async throws {
        XCTAssertTrue(try await extract(from: "marketplace-empty").isEmpty)
    }

    func testALoginPageYieldsNothing() async throws {
        // It must not throw, and it must not invent listings. The decision
        // that this IS a login wall belongs to LoginSignals, not here.
        XCTAssertTrue(try await extract(from: "marketplace-login").isEmpty)
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
```

- [ ] **Step 9: Add the fixtures to the test target**

In `project.yml`, the `PerchTests` target's `sources` currently reads
`sources: [PerchTests]`, which picks up `.swift` files but not `.html`. Replace
it with an explicit pair so the fixtures are copied into the test bundle:

```yaml
    sources:
      - PerchTests
      - path: PerchTests/Plugins/Market/Fixtures
        buildPhase: resources
```

Then `xcodegen generate`.

- [ ] **Step 10: Run the fixture tests**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/ExtractScriptTests 2>&1 | tail -25`
Expected: `** TEST SUCCEEDED **`, 8 tests

If `extractScriptSource()` throws `.scriptMissing`, `Bundle.module` is not
resolving from inside the app — **stop and report it** rather than inlining the
JavaScript as a Swift string. The whole point of the resource is that it can be
edited without recompiling.

- [ ] **Step 11: Run both suites**

Run: `swift test --package-path Plugins/MarketPlugin` then
`xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: both suites green. Exact counts shift as tests move between suites — do not treat a specific number as the gate; a failure is the gate.

- [ ] **Step 12: Commit**

```bash
git add Plugins/MarketPlugin PerchTests/Plugins/Market project.yml
git commit -m "feat: extract.js and its fixture tests"
```

---

### Task 4: The poller's reentrancy guard and empty-run detection

Both deferred from Plan 1 with "must fix before a real source goes behind the seam". It is about to.

**Files:**
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Poller/WatchPoller.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/WatchPollerTests.swift`

**Interfaces:**
- Produces: `WatchPoller.isScrapingHealthy: Bool` (false once the empty-run threshold is reached) and `WatchPoller.emptyRunThreshold = 3`. `tick()` returns `[]` immediately if another `tick()` is in flight.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/MarketPluginTests/WatchPollerTests.swift`:

```swift
    func testASecondTickIsRefusedWhileTheFirstIsStillRunning() async {
        // Sign-in and the background loop can now overlap. Two ticks
        // interleaving would double-poll and interleave store writes.
        let store = makeStore()
        let market = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)

        let gate = AsyncGate()
        market.beforeReturning = { await gate.wait() }

        async let first = poller.tick()
        await Task.yield()
        let second = await poller.tick()
        await gate.open()
        _ = await first

        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(market.calls.count, 1)
    }

    func testScrapingIsHealthyBeforeAnyPoll() {
        let poller = makePoller(store: makeStore(), source: FakeListingSource())

        XCTAssertTrue(poller.isScrapingHealthy)
    }

    func testConsecutiveEmptyRunsEventuallyReportUnhealthy() async {
        let store = makeStore()
        let market = FakeListingSource()  // returns nothing
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)

        for _ in 0..<WatchPoller.emptyRunThreshold {
            _ = await poller.tick()
            clock.advance(WatchPoller.minIntervalSeconds * 2)
        }

        XCTAssertFalse(poller.isScrapingHealthy)
    }

    func testOneShortOfTheThresholdIsStillHealthy() async {
        let store = makeStore()
        let market = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)

        for _ in 0..<(WatchPoller.emptyRunThreshold - 1) {
            _ = await poller.tick()
            clock.advance(WatchPoller.minIntervalSeconds * 2)
        }

        XCTAssertTrue(poller.isScrapingHealthy)
    }

    func testAnyScrapedListingRestoresHealth() async {
        // Counts listings SCRAPED, not listings that were new — a watch that
        // keeps returning the same ten results is working fine.
        let store = makeStore()
        let market = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)
        for _ in 0..<WatchPoller.emptyRunThreshold {
            _ = await poller.tick()
            clock.advance(WatchPoller.minIntervalSeconds * 2)
        }

        market.results = [scraped("a")]
        _ = await poller.tick()

        XCTAssertTrue(poller.isScrapingHealthy)
    }

    func testTheSameListingsAgainStillCountAsHealthy() async {
        let store = makeStore()
        let market = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)

        for _ in 0..<(WatchPoller.emptyRunThreshold + 2) {
            _ = await poller.tick()  // nothing NEW after the first
            clock.advance(WatchPoller.minIntervalSeconds * 2)
        }

        XCTAssertTrue(poller.isScrapingHealthy)
    }

    func testATickThatPollsNothingDoesNotCountAsEmpty() async {
        // No watches due is not evidence that scraping is broken.
        let store = makeStore()
        let market = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)
        _ = await poller.tick()  // one real empty run

        for _ in 0..<10 {
            _ = await poller.tick()  // nothing due; must not accumulate
        }

        XCTAssertTrue(poller.isScrapingHealthy)
    }

    func testBeingSignedOutDoesNotCountAsAnEmptyRun() async {
        // Signed out has its own state and its own message.
        let store = makeStore()
        let market = FakeListingSource()
        market.error = .signedOut
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: market)

        for _ in 0..<(WatchPoller.emptyRunThreshold + 2) {
            _ = await poller.tick()
            clock.advance(WatchPoller.signInRetrySeconds * 2)
        }

        XCTAssertTrue(poller.isScrapingHealthy)
    }
```

Add to `MarketTestSupport.swift`, beside the existing fakes:

```swift
/// Lets a test hold a fake's `search` open until it chooses to release it.
actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
```

and give `FakeListingSource` the hook the reentrancy test needs, without
disturbing its existing behaviour:

```swift
    /// Called inside `search`, before it returns. Lets a test suspend a poll
    /// in flight.
    var beforeReturning: (() async -> Void)?
```

invoked at the top of `search`, after recording the call:

```swift
        if let beforeReturning { await beforeReturning() }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Plugins/MarketPlugin --filter WatchPollerTests`
Expected: FAIL — `value of type 'WatchPoller' has no member 'isScrapingHealthy'`

- [ ] **Step 3: Implement**

In `Poller/WatchPoller.swift`, add beside the other constants:

```swift
    /// Consecutive polling rounds that scraped nothing at all before we stop
    /// believing the scraper works. Three is roughly 45 minutes at the default
    /// interval — late enough to be sure, early enough to be useful.
    public static let emptyRunThreshold = 3
```

Add the observable state and the private counters:

```swift
    /// False once several consecutive rounds have scraped nothing whatsoever.
    ///
    /// A quiet search is normal; every watch returning zero listings, round
    /// after round, usually means the selectors broke or the session died in a
    /// way login detection missed. The panel says so rather than showing
    /// nothing and letting the user assume it is working.
    public var isScrapingHealthy: Bool { consecutiveEmptyRuns < Self.emptyRunThreshold }

    @ObservationIgnored private var consecutiveEmptyRuns = 0
    @ObservationIgnored private var isTicking = false
```

Wrap the body of `tick()`:

```swift
    @discardableResult
    public func tick() async -> [(UUID, Int)] {
        // Sign-in, the background loop, and any future "poll now" can all
        // reach here. `tick()` was written assuming it never runs concurrently
        // with itself; two overlapping runs would double-poll and interleave
        // store writes.
        guard !isTicking else { return [] }
        isTicking = true
        defer { isTicking = false }

        ... existing body ...
    }
```

Track scraped counts. Declare a local beside `results` at the top of the loop
section:

```swift
        var scrapedAnything = false
        var polledAnything = false
```

set them where the search succeeds, right after `let scraped = try await ...`:

```swift
                polledAnything = true
                if !scraped.isEmpty { scrapedAnything = true }
```

and update the counter just before each `return` that follows a real polling
round — the normal end of the method, and the `signedOut` early return. At the
normal end, before `return results`:

```swift
        // Only a round that actually polled something is evidence either way.
        if polledAnything {
            consecutiveEmptyRuns = scrapedAnything ? 0 : consecutiveEmptyRuns + 1
        }
```

The `signedOut` path returns before this and must **not** touch the counter:
being signed out has its own state and its own message, and counting it here
would show two different explanations for one problem.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 122 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: reentrancy guard and empty-run detection"
```

---

### Task 5: `FacebookSession`

The thin, browser-bound part. Everything decidable without a browser was extracted in Tasks 1–3, so what is left here is navigation and plumbing.

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/FacebookSession.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketplaceURLTests.swift`

**Interfaces:**
- Consumes: `LoginSignals`, `isLoginWall`, `extractScriptSource`, `decodeExtractedListings`, `SearchError`.
- Produces: `marketplaceSearchURL(query:maxPrice:location:radiusKm:) -> URL?` (pure, testable); `@MainActor final class FacebookSession` with `init(navigationTimeout: TimeInterval = 30)`, `func loadResults(url: URL) async throws -> [ScrapedListing]`, `var webView: WKWebView { get }`, `func presentForSignIn()`/`func dismissSignIn()` hooks used by Task 7.

- [ ] **Step 1: Write the failing URL test**

`Tests/MarketPluginTests/MarketplaceURLTests.swift`:

```swift
@testable import MarketPlugin
import XCTest

final class MarketplaceURLTests: XCTestCase {
    func testTheCityIsInThePath() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertTrue(url.path.hasPrefix("/marketplace/auckland/search"))
    }

    func testTheQueryIsEncoded() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(
                query: "GoPro Hero 12", maxPrice: nil, location: "auckland", radiusKm: 50
            )
        )

        XCTAssertTrue(url.absoluteString.contains("query=GoPro%20Hero%2012"))
    }

    func testThePriceCapIsIncludedWhenSet() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)
        )

        XCTAssertTrue(url.absoluteString.contains("maxPrice=200"))
    }

    func testThePriceCapIsOmittedWhenUnset() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertFalse(url.absoluteString.contains("maxPrice"))
    }

    func testTheRadiusIsIncluded() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 20)
        )

        XCTAssertTrue(url.absoluteString.contains("radius=20"))
    }

    func testABlankLocationHasNoURL() {
        XCTAssertNil(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "  ", radiusKm: 50)
        )
    }

    func testItIsAlwaysHTTPSOnFacebook() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.facebook.com")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketplaceURLTests`
Expected: FAIL — `cannot find 'marketplaceSearchURL' in scope`

- [ ] **Step 3: Write the session**

`Sources/MarketPlugin/Session/FacebookSession.swift`:

```swift
import Foundation
import WebKit

/// The search URL for a watch, or `nil` when there is no city to search in.
///
/// Pure, so the URL shape is pinned by tests rather than discovered in
/// production.
public func marketplaceSearchURL(
    query: String, maxPrice: Int?, location: String, radiusKm: Int
) -> URL? {
    let city = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !city.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.facebook.com"
    components.path = "/marketplace/\(city)/search"
    var items = [
        URLQueryItem(name: "query", value: query),
        URLQueryItem(name: "radius", value: String(radiusKm)),
    ]
    if let maxPrice { items.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
    components.queryItems = items
    return components.url
}

/// Owns the one `WKWebView` everything Facebook-shaped goes through.
///
/// On `WKWebsiteDataStore.default()`, so the sign-in cookie survives quitting
/// Perch. The superseded Python sidecar signed in once per *run* and could not
/// do better without forking its upstream; this is the single biggest reason
/// the rewrite was worth it.
///
/// One webview also makes the poller's serial guarantee structural rather than
/// a matter of discipline.
@MainActor
public final class FacebookSession: NSObject {
    /// A `WKWebView` load can hang with no delegate callback ever arriving.
    /// Without a deadline that wedges the poller permanently.
    private let navigationTimeout: TimeInterval

    public let webView: WKWebView

    /// Parked offscreen while polling: a webview outside a window may not lay
    /// out or run scripts reliably, and we need it live without showing it.
    private let hiddenWindow: NSWindow
    private var pendingLoad: CheckedContinuation<Void, Error>?

    public init(navigationTimeout: TimeInterval = 30) {
        self.navigationTimeout = navigationTimeout

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration
        )

        hiddenWindow = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1280, height: 900),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        hiddenWindow.title = "Market"
        hiddenWindow.contentView = webView
        hiddenWindow.orderBack(nil)

        super.init()
        webView.navigationDelegate = self
    }

    /// Loads a results page and returns whatever `extract.js` finds on it.
    ///
    /// Throws `SearchError.signedOut` when the page is a login wall, and
    /// `SearchError.failed` when navigation fails or times out.
    public func loadResults(url: URL) async throws -> [ScrapedListing] {
        try await navigate(to: url)

        let script = try extractScriptSource()
        let raw = try await evaluate(script)
        let listings = try decodeExtractedListings(raw)

        let signals = LoginSignals(
            urlPath: webView.url?.path ?? "",
            hasPasswordField: try await evaluateBool(
                "document.querySelector('input[type=\"password\"]') !== null"
            ),
            hasLoginForm: try await evaluateBool(
                "document.querySelector('form[action*=\"login\"]') !== null"
            ),
            listingCount: listings.count
        )
        if isLoginWall(signals) { throw SearchError.signedOut }

        return listings
    }

    // MARK: - Navigation

    private func navigate(to url: URL) async throws {
        webView.stopLoading()
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.pendingLoad = continuation
                    self.webView.load(URLRequest(url: url))
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(for: .seconds(self.navigationTimeout))
                self.finishLoad(throwing: SearchError.failed("navigation timed out"))
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func finishLoad(throwing error: Error?) {
        guard let continuation = pendingLoad else { return }
        pendingLoad = nil
        if let error {
            webView.stopLoading()
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func evaluate(_ script: String) async throws -> String {
        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let string = result as? String else {
                throw SearchError.failed("the page returned no listings payload")
            }
            return string
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.failed("could not read the page")
        }
    }

    private func evaluateBool(_ script: String) async throws -> Bool {
        (try? await webView.evaluateJavaScript(script)) as? Bool ?? false
    }
}

extension FacebookSession: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(throwing: nil)
    }

    public func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        finishLoad(throwing: SearchError.failed(error.localizedDescription))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoad(throwing: SearchError.failed(error.localizedDescription))
    }
}
```

- [ ] **Step 4: Run the URL tests**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 129 tests, 0 failures

- [ ] **Step 5: Note what is untested, honestly**

`FacebookSession`'s navigation, timeout, and delegate plumbing are not unit
tested — they need a browser and, for anything meaningful, a network. That is
stated in the report rather than covered by a test that asserts nothing. The
pure parts around it (URL building, login judgement, decoding, price parsing)
are all tested.

- [ ] **Step 6: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: FacebookSession over a shared-cookie WKWebView"
```

---

### Task 6: `FacebookListingSource` and the swap

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/FacebookListingSource.swift`
- Delete: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/StubListingSource.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Market.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketPluginTests.swift` (fix existing references)
- Test: `PerchTests/Plugins/Market/MarketSessionWiringTests.swift`

**Interfaces:**
- Consumes: `FacebookSession`, `marketplaceSearchURL`, `ListingSource`.
- Produces: `FacebookListingSource(session: FacebookSession)` conforming to `ListingSource`; `Market.session: FacebookSession?` exposed so Task 7's sign-in window can reach the webview.

- [ ] **Step 1: Write the failing test**

These go in the **app-hosted** suite, not the package one. The production
initializer builds a `FacebookSession`, which creates a `WKWebView` and an
`NSWindow` — neither is safe in `swift test`, which runs with no `NSApplication`.

`PerchTests/Plugins/Market/MarketSessionWiringTests.swift`:

```swift
@testable import MarketPlugin
import PerchKit
import XCTest

@MainActor
final class MarketSessionWiringTests: XCTestCase {
    private func context() -> PluginContext {
        PluginContext(
            storage: PluginStorage(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("MarketWiring-\(UUID().uuidString)")
            ),
            defaults: PluginDefaults(
                suite: UserDefaults(suiteName: "MarketWiring-\(UUID().uuidString)")!,
                prefix: Market.identifier
            )
        )
    }

    func testTheDefaultInitializerUsesARealSource() {
        // The production path must not be wired to a stub. This is the whole
        // deliverable of Plan 2 in one assertion.
        let plugin = Market(context: context())

        XCTAssertNotNil(plugin.session)
    }

    func testTheTestableInitializerHasNoSession() {
        // Injecting a fake source must not spin up a WKWebView.
        let plugin = Market(context: context(), source: FakeSource())

        XCTAssertNil(plugin.session)
    }
}

/// A do-nothing source, local to this file — `MarketTestSupport`'s fake lives
/// in the package test target and is not visible here.
@MainActor
private struct FakeSource: ListingSource {
    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] { [] }
}
```

Separately, in `Tests/MarketPluginTests/MarketPluginTests.swift`, the package
suite's `makePlugin()` currently passes `StubListingSource()`, which this task
deletes. Point it at `FakeListingSource()` from `MarketTestSupport.swift`
instead — and confirm no other reference to `StubListingSource` survives
anywhere:

```bash
grep -rn "StubListingSource" Plugins PerchTests
```

must come back empty once the task is done.

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketPluginTests`
Expected: FAIL — `value of type 'Market' has no member 'session'`

- [ ] **Step 3: Write the source**

`Sources/MarketPlugin/Session/FacebookListingSource.swift`:

```swift
import Foundation

/// The real `ListingSource`: a Facebook Marketplace search, through the
/// session's webview.
@MainActor
public struct FacebookListingSource: ListingSource {
    private let session: FacebookSession

    public init(session: FacebookSession) {
        self.session = session
    }

    public func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        guard let url = marketplaceSearchURL(
            query: query, maxPrice: maxPrice, location: location, radiusKm: radiusKm
        ) else {
            // The store refuses to create a watch without a location, so this
            // means a watch predating that rule, or a location edited to
            // nothing. Permanent for this watch, not worth retrying hard —
            // but `failed` is the honest classification, since a human fixing
            // the setting does resolve it.
            throw SearchError.failed("this watch has no location set")
        }
        return try await session.loadResults(url: url)
    }
}
```

- [ ] **Step 4: Swap it in**

Delete `Session/StubListingSource.swift`.

In `Market.swift`, hold the session and use it in the production initializer:

```swift
    /// Non-nil only on the production path. Tests inject a fake source and get
    /// no webview.
    public private(set) var session: FacebookSession?

    public required convenience init(context: PluginContext) {
        let session = FacebookSession()
        self.init(context: context, source: FacebookListingSource(session: session))
        self.session = session
    }
```

A convenience initializer cannot assign a stored property after `self.init`
unless the property is a `var` — it is, above. If the compiler objects, restructure
so the designated initializer takes an optional session rather than fighting it.

- [ ] **Step 5: Run both suites**

Run: `swift test --package-path Plugins/MarketPlugin` then
`xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: both suites green. Exact counts shift as tests move between suites — do not treat a specific number as the gate; a failure is the gate.

- [ ] **Step 6: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: swap the stub for a real Facebook source"
```

---

### Task 7: The sign-in window

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/SignInWindow.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/FacebookSession.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/MarketPanelView.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Market.swift`

**Interfaces:**
- Consumes: `FacebookSession`, `PollerState`.
- Produces: `FacebookSession.presentForSignIn()` and `FacebookSession.isShowingSignIn: Bool`; the panel's signed-out row becomes a button that calls it.

- [ ] **Step 1: Give the session a visible mode**

In `FacebookSession.swift`, add:

```swift
    /// Whether the sign-in window is on screen.
    public private(set) var isShowingSignIn = false

    /// Brings the webview on screen so the user can sign in to Facebook.
    ///
    /// The *same* webview the scraper uses — a second one would put the cookie
    /// in the wrong data store. Nothing times the user out and nothing closes
    /// the window underneath them; the Python version gave them 60 seconds and
    /// then tore the window down mid-2FA, which is the failure this exists to
    /// avoid.
    public func presentForSignIn() {
        webView.load(URLRequest(url: URL(string: "https://www.facebook.com/login")!))
        hiddenWindow.setContentSize(NSSize(width: 1024, height: 800))
        hiddenWindow.center()
        hiddenWindow.title = "Sign in to Facebook"
        hiddenWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isShowingSignIn = true
    }

    /// Returns the webview to its offscreen parking spot.
    public func dismissSignIn() {
        hiddenWindow.orderOut(nil)
        hiddenWindow.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        isShowingSignIn = false
    }
```

Perch is `LSUIElement`, so `NSApp.activate` is what actually brings the window
forward; without it the window appears behind whatever the user is using.

- [ ] **Step 2: Close it when the user finishes**

Still in `FacebookSession.swift`, in the `didFinish` delegate method, add
before `finishLoad(throwing: nil)`:

```swift
        // Signed in and back on a real Facebook page: the window has done its
        // job. Judged by URL rather than by a button click, because Facebook's
        // login flow has several steps and only the destination is stable.
        if isShowingSignIn,
           let path = webView.url?.path,
           !path.contains("/login"),
           !path.contains("/checkpoint") {
            dismissSignIn()
        }
```

- [ ] **Step 3: Wire the panel**

In `MarketPanelView.swift`, the `.signedOut` branch of `statusLine` currently
renders a `Label`. Make it actionable:

```swift
        case .signedOut:
            Button {
                onSignIn?()
            } label: {
                Label("Sign in to Facebook", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Opens a window where you can sign in to Facebook")
```

Add the closure as a property beside the existing ones:

```swift
    let onSignIn: (() -> Void)?
```

- [ ] **Step 4: Add the unhealthy-scraping row**

In the same `statusLine`, before the `.idle, .polling` case, surface the
condition Task 4 detects:

```swift
        case .idle, .polling where !poller.isScrapingHealthy:
            Text("Facebook may have changed — check your sign-in")
                .font(.caption)
                .foregroundStyle(.orange)
```

Swift requires the `where` clause to apply to the whole case list, so write it
as its own case above the plain `.idle, .polling` one:

```swift
        case .idle, .polling:
            if poller.isScrapingHealthy {
                EmptyView()
            } else {
                Text("Facebook may have changed — check your sign-in")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
```

- [ ] **Step 5: Pass it through**

In `Market.swift`, hand the panel a way to open sign-in:

```swift
    public var panel: AnyView {
        AnyView(
            MarketPanelView(
                store: store,
                poller: poller,
                onSignIn: session.map { session in { session.presentForSignIn() } }
            )
        )
    }
```

- [ ] **Step 6: Run both suites**

Run: `swift test --package-path Plugins/MarketPlugin` then
`xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: both suites green. Exact counts shift as tests move between suites — do not treat a specific number as the gate; a failure is the gate. No new tests here —
window presentation is not unit-testable in this setup, and a test asserting a
window exists would prove nothing about whether signing in works.

- [ ] **Step 7: Build the app and hand the check to the user**

**Do not click through the app yourself.** Build it and stop:

```bash
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```

Then report this, for the user to run when they choose:

1. Open the Market tab. If it says "Sign in to Facebook", click it.
2. A window opens on facebook.com. Sign in. Take as long as you need.
3. The window should close by itself once you land on a normal Facebook page.
4. Within a few minutes the watch should show found listings.
5. Quit Perch and reopen it. You should still be signed in — that is the thing
   the Python version could never do.

If step 4 produces nothing, the likely cause is `extract.js`'s selectors not
matching today's Facebook, which the hand-built fixtures cannot catch. The fix
is to save that results page and turn it into a real fixture.

- [ ] **Step 8: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: sign-in window"
```

---

## What this plan does not do

- **The full Market window** — listing history, per-watch detail, a settings pane — is Plan 3. This builds only the sign-in window.
- **Notifications on new finds.** `.notifications` is declared and the settings toggle is disabled with a "coming soon" note.
- **Real fixtures.** The ones here are hand-built. Replacing them needs a saved page from a signed-in session, which is the user's to provide.
