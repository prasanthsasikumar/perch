# Market Plugin — Core Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third Perch tab — Market — that holds watches, records findings, schedules polls, and renders the panel, working end to end against a fake listing source. No Facebook, no WKWebView, no network.

**Architecture:** A Swift package `Plugins/MarketPlugin` depending on `PerchKit`, following `AnalyticsPlugin`'s shape: an `@Observable` store persisting one JSON document through `PluginStorage`, a poller with an injected clock, and SwiftUI views. Everything that will eventually touch Facebook sits behind a `ListingSource` protocol that Plan 2 implements for real; Plan 1 ships a fake.

**Tech Stack:** Swift 5.9, macOS 14, SwiftUI, Observation, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-08-market-plugin-design.md`

## Global Constraints

- macOS 14, `swift-tools-version: 5.9`, matching the other plugin packages.
- Tests are **XCTest**, in the package's own test target at `Plugins/MarketPlugin/Tests/MarketPluginTests/`, run with `swift test`. This is a deliberate departure from Perch's convention of putting every test in the app-hosted `PerchTests` target, and the justification is speed: package tests need no app host and the whole Market suite runs in ~0.26s, against ~10s for the same tests through `xcodebuild`. Across a TDD loop that difference dominates. Anything genuinely host-dependent — Plan 2's `WKWebView` fixture tests, for instance — belongs in `PerchTests`, which works fine.

  **Correction:** an earlier version of this line claimed the app-hosted suite hangs on this machine and was therefore unusable. That was wrong. Two 345-second timeouts were observed while a stalled background `xcodebuild` was live or had just been killed, and I generalised from them without isolating the cause. The suite passes in 6–10 seconds, including with `Perch.app` already running and with two concurrent runs on the same scheme — both of which were tested and refuted as causes. The original trigger was never reproduced.
- **No test may touch the network, launch a browser, or write outside a temporary directory.** Plan 1 contains no networking code at all.
- Plugin identifier is `org.ahlab.perch.market` and must never change — it names the storage directory and the `UserDefaults` prefix.
- Display name **Market**, SF Symbol **`binoculars`**, capabilities `.network` and `.notifications`.
- Poll policy, fixed by the spec and not a tuning preference: strictly serial, `minIntervalSeconds = 600` floor per watch, 15-minute default interval, ±20% jitter, backoff capped at `maxBackoffSeconds = 7200`. Jitter must never schedule below the floor.
- Listings are capped at **200 per watch**, oldest dropped.
- A watch cannot be created while `settings.location` is `nil`. No default city ships.
- `Package.swift` files are generated-adjacent config: after editing `project.yml`, run `xcodegen generate`.
- Do not modify `PerchKit`. If something seems to require it, stop and report.

## Test command

The whole suite:

```bash
swift test --package-path Plugins/MarketPlugin
```

A single class, which is what you want while iterating:

```bash
swift test --package-path Plugins/MarketPlugin --filter MarketStoreTests
```

Both take seconds. **Do not run these in the background** — run them in the
foreground and let them block.

Do not reach for `xcodebuild test`. It hangs on this machine for reasons that
have nothing to do with this plugin, and waiting on it is how the first attempt
at Task 1 stalled twice.

---

### Task 1: Package scaffold and models

**Files:**
- Create: `Plugins/MarketPlugin/Package.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Models/Watch.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Models/Listing.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Models/MarketSettings.swift`
- Modify: `project.yml`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/ModelTests.swift`

**Interfaces:**
- Consumes: `PerchKit` only.
- Produces: `Watch(id:query:maxPrice:location:radiusKm:paused:createdAt:lastCheckedAt:consecutiveFailures:nextCheckAt:)`, `Listing(id:watchID:title:price:location:url:imageURL:firstSeenAt:seen:)`, `MarketSettings(location:radiusKm:pollIntervalMinutes:notificationsEnabled:)` with `MarketSettings.defaults`.

- [ ] **Step 1: Create the package**

`Plugins/MarketPlugin/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarketPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarketPlugin", targets: ["MarketPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "MarketPlugin", dependencies: ["PerchKit"]),
        // PerchKit is listed explicitly even though MarketPlugin already
        // depends on it: later tests construct a PluginContext and a
        // PluginStorage directly, and relying on a transitive import is
        // fragile.
        .testTarget(name: "MarketPluginTests", dependencies: ["MarketPlugin", "PerchKit"]),
    ]
)
```

The test target is the one place this package differs from `MenuDoPlugin` and
`AnalyticsPlugin`. Perch's convention puts every test in the app-hosted
`PerchTests` target, but that suite does not currently run on this machine —
see Global Constraints. These tests need no app host, so they live here and
run in seconds.

- [ ] **Step 2: Register the package with the Xcode project**

In `project.yml`, add to `packages:` (after `AnalyticsPlugin`):

```yaml
  MarketPlugin:
    path: Plugins/MarketPlugin
```

Add to the `Perch` target's `dependencies:`:

```yaml
      - package: MarketPlugin
        product: MarketPlugin
```

Add the same two lines to the `PerchTests` target's `dependencies:` too — the app-hosted suite does not run this plugin's tests, but Plan 2 may add host-level ones and the dependency costs nothing.

Then regenerate:

```bash
xcodegen generate
```

- [ ] **Step 3: Write the failing test**

`Plugins/MarketPlugin/Tests/MarketPluginTests/ModelTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import XCTest

final class ModelTests: XCTestCase {
    func testANewWatchIsDueImmediately() {
        let watch = Watch(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)

        XCTAssertEqual(watch.nextCheckAt, .distantPast)
        XCTAssertNil(watch.lastCheckedAt)
        XCTAssertEqual(watch.consecutiveFailures, 0)
        XCTAssertFalse(watch.paused)
    }

    func testAWatchRoundTripsThroughJSON() throws {
        let watch = Watch(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)

        let data = try JSONEncoder().encode(watch)
        let decoded = try JSONDecoder().decode(Watch.self, from: data)

        XCTAssertEqual(decoded, watch)
    }

    func testAWatchWithNoPriceCapRoundTrips() throws {
        let watch = Watch(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)

        let decoded = try JSONDecoder().decode(
            Watch.self, from: try JSONEncoder().encode(watch)
        )

        XCTAssertNil(decoded.maxPrice)
    }

    func testANewListingIsUnseen() {
        let listing = Listing(
            id: "123",
            watchID: UUID(),
            title: "GoPro Hero 12",
            price: "$180",
            location: "Auckland",
            url: URL(string: "https://facebook.com/marketplace/item/123")!,
            imageURL: nil
        )

        XCTAssertFalse(listing.seen)
    }

    func testAListingRoundTripsThroughJSON() throws {
        let listing = Listing(
            id: "123",
            watchID: UUID(),
            title: "GoPro Hero 12",
            price: "$180",
            location: "Auckland",
            url: URL(string: "https://facebook.com/marketplace/item/123")!,
            imageURL: URL(string: "https://img.example/1.jpg")
        )

        let decoded = try JSONDecoder().decode(
            Listing.self, from: try JSONEncoder().encode(listing)
        )

        XCTAssertEqual(decoded, listing)
    }

    func testSettingsDefaultToNoLocation() {
        let settings = MarketSettings.defaults

        XCTAssertNil(settings.location)
        XCTAssertEqual(settings.radiusKm, 50)
        XCTAssertEqual(settings.pollIntervalMinutes, 15)
        XCTAssertTrue(settings.notificationsEnabled)
    }
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter ModelTests`
Expected: FAIL — `no such module 'MarketPlugin'` or `cannot find 'Watch' in scope`

- [ ] **Step 5: Write the models**

`Models/Watch.swift`:

```swift
import Foundation

/// One saved search.
///
/// `location` and `radiusKm` are copied from settings when the watch is
/// created rather than read live, so changing the default later does not
/// silently move searches the user already set up.
public struct Watch: Identifiable, Codable, Equatable {
    public let id: UUID
    public var query: String
    public var maxPrice: Int?
    public var location: String
    public var radiusKm: Int
    public var paused: Bool
    public let createdAt: Date
    public var lastCheckedAt: Date?
    public var consecutiveFailures: Int
    /// `.distantPast` means "due now", which is what a new watch wants.
    public var nextCheckAt: Date

    public init(
        id: UUID = UUID(),
        query: String,
        maxPrice: Int?,
        location: String,
        radiusKm: Int,
        paused: Bool = false,
        createdAt: Date = .now,
        lastCheckedAt: Date? = nil,
        consecutiveFailures: Int = 0,
        nextCheckAt: Date = .distantPast
    ) {
        self.id = id
        self.query = query
        self.maxPrice = maxPrice
        self.location = location
        self.radiusKm = radiusKm
        self.paused = paused
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.consecutiveFailures = consecutiveFailures
        self.nextCheckAt = nextCheckAt
    }
}
```

`Models/Listing.swift`:

```swift
import Foundation

/// One listing found for one watch.
///
/// `id` is Facebook's listing id, and the pair (`watchID`, `id`) is what
/// "already found" means — two watches can legitimately both find the same
/// listing and each should report it once.
public struct Listing: Identifiable, Codable, Equatable {
    public let id: String
    public let watchID: UUID
    public var title: String
    public var price: String
    public var location: String
    public var url: URL
    public var imageURL: URL?
    public let firstSeenAt: Date
    /// Whether the user has looked at it — distinct from having fetched it.
    public var seen: Bool

    public init(
        id: String,
        watchID: UUID,
        title: String,
        price: String,
        location: String,
        url: URL,
        imageURL: URL?,
        firstSeenAt: Date = .now,
        seen: Bool = false
    ) {
        self.id = id
        self.watchID = watchID
        self.title = title
        self.price = price
        self.location = location
        self.url = url
        self.imageURL = imageURL
        self.firstSeenAt = firstSeenAt
        self.seen = seen
    }
}
```

`Models/MarketSettings.swift`:

```swift
import Foundation

/// Settings shared by every watch.
///
/// `location` has no default on purpose. Facebook scopes marketplace searches
/// to a city, and a wrong city returns nothing just as silently as no city —
/// so the user is asked rather than guessed at.
public struct MarketSettings: Codable, Equatable {
    public var location: String?
    public var radiusKm: Int
    public var pollIntervalMinutes: Int
    public var notificationsEnabled: Bool

    public init(
        location: String? = nil,
        radiusKm: Int = 50,
        pollIntervalMinutes: Int = 15,
        notificationsEnabled: Bool = true
    ) {
        self.location = location
        self.radiusKm = radiusKm
        self.pollIntervalMinutes = pollIntervalMinutes
        self.notificationsEnabled = notificationsEnabled
    }

    public static let defaults = MarketSettings()
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter ModelTests`
Expected: `** TEST SUCCEEDED **`, 6 tests

- [ ] **Step 7: Commit**

```bash
git add Plugins/MarketPlugin project.yml
git commit -m "feat: Market plugin package and models"
```

---

### Task 2: The new-vs-seen diff

This is the correctness claim the whole plugin rests on: a listing is reported exactly once, never missed and never announced twice. It is a free function over two collections so it can be tested without a store, a clock, or a view.

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Store/NewListings.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/NewListingsTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ScrapedListing(id:title:price:location:url:imageURL:)` and `newListings(_ fetched: [ScrapedListing], seenIDs: Set<String>) -> [ScrapedListing]`.

- [ ] **Step 1: Write the failing test**

`Plugins/MarketPlugin/Tests/MarketPluginTests/NewListingsTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import XCTest

func scraped(_ id: String, title: String = "Item") -> ScrapedListing {
    ScrapedListing(
        id: id,
        title: title,
        price: "$100",
        location: "Auckland",
        url: URL(string: "https://facebook.com/marketplace/item/\(id)")!,
        imageURL: nil
    )
}

final class NewListingsTests: XCTestCase {
    func testEverythingIsNewWhenNothingHasBeenSeen() {
        let found = newListings([scraped("a"), scraped("b")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["a", "b"])
    }

    func testAlreadySeenListingsAreExcluded() {
        let found = newListings([scraped("a"), scraped("b")], seenIDs: ["a"])

        XCTAssertEqual(found.map(\.id), ["b"])
    }

    func testDuplicatesWithinOneFetchAreCollapsed() {
        // Facebook repeats listings as you scroll; reporting twice is a bug.
        let found = newListings([scraped("a"), scraped("a")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["a"])
    }

    func testTheFirstOfADuplicatePairIsKept() {
        let found = newListings(
            [scraped("a", title: "first"), scraped("a", title: "second")], seenIDs: []
        )

        XCTAssertEqual(found.first?.title, "first")
    }

    func testFetchOrderIsPreserved() {
        let found = newListings([scraped("c"), scraped("a"), scraped("b")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["c", "a", "b"])
    }

    func testNothingNewYieldsAnEmptyResult() {
        XCTAssertTrue(newListings([scraped("a")], seenIDs: ["a"]).isEmpty)
    }

    func testAnEmptyFetchYieldsAnEmptyResult() {
        XCTAssertTrue(newListings([], seenIDs: ["a"]).isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter NewListingsTests`
Expected: FAIL — `cannot find 'ScrapedListing' in scope`

- [ ] **Step 3: Write the implementation**

`Store/NewListings.swift`:

```swift
import Foundation

/// A listing as it comes off the page, before it belongs to a watch.
public struct ScrapedListing: Equatable, Sendable {
    public let id: String
    public let title: String
    public let price: String
    public let location: String
    public let url: URL
    public let imageURL: URL?

    public init(
        id: String,
        title: String,
        price: String,
        location: String,
        url: URL,
        imageURL: URL?
    ) {
        self.id = id
        self.title = title
        self.price = price
        self.location = location
        self.url = url
        self.imageURL = imageURL
    }
}

/// The listings in `fetched` that are not already in `seenIDs`, deduplicated.
///
/// Fetch order is preserved and the first of any duplicate pair wins, so the
/// freshest scrape of a listing is the one recorded. This is the one piece of
/// logic whose failure a user would actually notice — as a missed find, or as
/// the same listing announced twice.
public func newListings(
    _ fetched: [ScrapedListing], seenIDs: Set<String>
) -> [ScrapedListing] {
    var already = seenIDs
    var result: [ScrapedListing] = []
    for listing in fetched where !already.contains(listing.id) {
        already.insert(listing.id)
        result.append(listing)
    }
    return result
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter NewListingsTests`
Expected: `** TEST SUCCEEDED **`, 7 tests

- [ ] **Step 5: Commit**

```bash
git add Plugins/MarketPlugin/Sources/MarketPlugin/Store/NewListings.swift Plugins/MarketPlugin/Tests/MarketPluginTests/NewListingsTests.swift
git commit -m "feat: new-vs-seen diff"
```

---

### Task 3: The store

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Store/MarketDocument.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Store/MarketStore.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketStoreTests.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketTestSupport.swift`

**Interfaces:**
- Consumes: `Watch`, `Listing`, `MarketSettings`, `ScrapedListing`, `newListings`.
- Produces: `MarketStore(storage:filename:)` with `watches: [Watch]`, `settings: MarketSettings`, `loadFailureNotice: String?`, `canAddWatch: Bool`, `addWatch(query:maxPrice:) -> Watch?`, `deleteWatch(id:)`, `update(_ watch: Watch)`, `updateSettings(_:)`, `record(_ scraped: [ScrapedListing], for watchID: UUID) -> [Listing]`, `listings(for watchID: UUID) -> [Listing]`, `newest(for watchID: UUID, limit: Int) -> [Listing]`, `unseenCount(for watchID: UUID) -> Int`, `markSeen(watchID: UUID)`, `totalUnseen: Int`, `saveNow()`. Also `MarketStore.listingsPerWatchCap = 200`.

- [ ] **Step 1: Write the failing test**

`Plugins/MarketPlugin/Tests/MarketPluginTests/MarketTestSupport.swift`. Note the `scraped(_:title:)`
helper you need here was already defined at file scope in
`NewListingsTests.swift` in Task 2 — it is visible across the whole test target,
so import nothing and do not redefine it:

```swift
import Foundation
import PerchKit

enum MarketFixture {
    static func temporaryStorage() -> PluginStorage {
        PluginStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MarketTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
```

`Plugins/MarketPlugin/Tests/MarketPluginTests/MarketStoreTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import PerchKit
import XCTest

@MainActor
final class MarketStoreTests: XCTestCase {
    private func configuredStore(
        storage: PluginStorage = MarketFixture.temporaryStorage()
    ) -> MarketStore {
        let store = MarketStore(storage: storage)
        store.updateSettings(MarketSettings(location: "auckland", radiusKm: 50))
        return store
    }

    func testAWatchCannotBeAddedBeforeALocationIsSet() {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())

        XCTAssertFalse(store.canAddWatch)
        XCTAssertNil(store.addWatch(query: "GoPro", maxPrice: 200))
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testAWatchCanBeAddedOnceALocationIsSet() {
        let store = configuredStore()

        XCTAssertTrue(store.canAddWatch)
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)

        XCTAssertEqual(watch?.query, "GoPro")
        XCTAssertEqual(store.watches.count, 1)
    }

    func testANewWatchTakesTheCurrentLocation() {
        let store = configuredStore()

        let watch = store.addWatch(query: "GoPro", maxPrice: 200)

        XCTAssertEqual(watch?.location, "auckland")
        XCTAssertEqual(watch?.radiusKm, 50)
    }

    func testChangingSettingsDoesNotMoveExistingWatches() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)!

        store.updateSettings(MarketSettings(location: "wellington", radiusKm: 20))

        XCTAssertEqual(store.watches.first(where: { $0.id == watch.id })?.location, "auckland")
    }

    func testABlankQueryIsRejected() {
        let store = configuredStore()

        XCTAssertNil(store.addWatch(query: "   ", maxPrice: nil))
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testAQueryIsStoredTrimmed() {
        let store = configuredStore()

        XCTAssertEqual(store.addWatch(query: "  GoPro  ", maxPrice: nil)?.query, "GoPro")
    }

    func testDeletingAWatchRemovesItsListings() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        store.deleteWatch(id: watch.id)

        XCTAssertTrue(store.watches.isEmpty)
        XCTAssertTrue(store.listings(for: watch.id).isEmpty)
    }

    func testRecordReturnsOnlyTheNewOnes() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        let fresh = store.record([scraped("a"), scraped("b")], for: watch.id)

        XCTAssertEqual(fresh.map(\.id), ["b"])
    }

    func testTwoWatchesTrackTheSameListingIndependently() {
        let store = configuredStore()
        let first = store.addWatch(query: "GoPro", maxPrice: nil)!
        let second = store.addWatch(query: "camera", maxPrice: nil)!
        _ = store.record([scraped("a")], for: first.id)

        let fresh = store.record([scraped("a")], for: second.id)

        XCTAssertEqual(fresh.map(\.id), ["a"])
    }

    func testNewlyRecordedListingsAreUnseen() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!

        _ = store.record([scraped("a"), scraped("b")], for: watch.id)

        XCTAssertEqual(store.unseenCount(for: watch.id), 2)
        XCTAssertEqual(store.totalUnseen, 2)
    }

    func testMarkSeenClearsTheCount() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)

        store.markSeen(watchID: watch.id)

        XCTAssertEqual(store.unseenCount(for: watch.id), 0)
    }

    func testListingsComeBackNewestFirst() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a")], for: watch.id)
        _ = store.record([scraped("b")], for: watch.id)

        XCTAssertEqual(store.listings(for: watch.id).map(\.id), ["b", "a"])
    }

    func testNewestTrimsToTheLimit() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("a"), scraped("b"), scraped("c")], for: watch.id)

        XCTAssertEqual(store.newest(for: watch.id, limit: 2).count, 2)
    }

    func testListingsAreCappedPerWatch() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        let many = (0..<(MarketStore.listingsPerWatchCap + 10)).map { scraped("id-\($0)") }

        _ = store.record(many, for: watch.id)

        XCTAssertEqual(store.listings(for: watch.id).count, MarketStore.listingsPerWatchCap)
    }

    func testTheCapDropsTheOldest() {
        let store = configuredStore()
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        _ = store.record([scraped("oldest")], for: watch.id)
        let many = (0..<MarketStore.listingsPerWatchCap).map { scraped("id-\($0)") }

        _ = store.record(many, for: watch.id)

        XCTAssertFalse(store.listings(for: watch.id).contains { $0.id == "oldest" })
    }

    func testStateSurvivesAReload() {
        let storage = MarketFixture.temporaryStorage()
        let store = configuredStore(storage: storage)
        let watch = store.addWatch(query: "GoPro", maxPrice: 200)!
        _ = store.record([scraped("a")], for: watch.id)
        store.saveNow()

        let reloaded = MarketStore(storage: storage)

        XCTAssertEqual(reloaded.watches.map(\.query), ["GoPro"])
        XCTAssertEqual(reloaded.settings.location, "auckland")
        XCTAssertEqual(reloaded.listings(for: watch.id).map(\.id), ["a"])
    }

    func testAFreshStoreStartsEmptyRatherThanFailing() {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())

        XCTAssertTrue(store.watches.isEmpty)
        XCTAssertNil(store.loadFailureNotice)
    }

    func testAnUnreadableDocumentIsReportedRatherThanSwallowed() throws {
        let storage = MarketFixture.temporaryStorage()
        try FileManager.default.createDirectory(
            at: storage.directory, withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: storage.url(named: "market.json"))

        let store = MarketStore(storage: storage)

        XCTAssertNotNil(store.loadFailureNotice)
        XCTAssertTrue(store.watches.isEmpty)
    }

    func testUpdatingAWatchReplacesItInPlace() {
        let store = configuredStore()
        var watch = store.addWatch(query: "GoPro", maxPrice: 200)!

        watch.consecutiveFailures = 3
        store.update(watch)

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 3)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketStoreTests`
Expected: FAIL — `cannot find 'MarketStore' in scope`

- [ ] **Step 3: Write the document type**

`Store/MarketDocument.swift`:

```swift
import Foundation

/// Everything the plugin persists, in one file.
///
/// One document rather than three keeps writes atomic: a save can never leave
/// watches and their listings disagreeing about what exists.
struct MarketDocument: Codable, Equatable {
    var watches: [Watch]
    var listings: [Listing]
    var settings: MarketSettings

    static let empty = MarketDocument(watches: [], listings: [], settings: .defaults)
}
```

- [ ] **Step 4: Write the store**

`Store/MarketStore.swift`:

```swift
import AppKit
import Foundation
import Observation
import PerchKit

/// The plugin's state, persisted as one JSON document.
///
/// Writes are debounced — a poll can record a dozen listings in a burst, and
/// rewriting the file per listing would be wasteful — but `flush()` on the
/// plugin and `willTerminate` both force a synchronous save, so nothing is
/// lost on quit.
@MainActor
@Observable
public final class MarketStore {
    /// Enough history for any view we show, and it bounds the file without a
    /// retention setting nobody would tune.
    public static let listingsPerWatchCap = 200

    public private(set) var watches: [Watch] = []
    public private(set) var settings: MarketSettings = .defaults
    public private(set) var loadFailureNotice: String?

    private var listingsByWatch: [UUID: [Listing]] = [:]
    private let storage: PluginStorage
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(storage: PluginStorage, filename: String = "market.json") {
        self.storage = storage
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Watches

    /// Facebook scopes marketplace searches to a city. Without one a search
    /// returns nothing while raising nothing, so we refuse rather than create
    /// a watch that can never match.
    public var canAddWatch: Bool {
        !(settings.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    @discardableResult
    public func addWatch(query: String, maxPrice: Int?) -> Watch? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAddWatch, let location = settings.location else { return nil }

        let watch = Watch(
            query: trimmed,
            maxPrice: maxPrice,
            location: location,
            radiusKm: settings.radiusKm
        )
        watches.append(watch)
        scheduleSave()
        return watch
    }

    public func deleteWatch(id: UUID) {
        watches.removeAll { $0.id == id }
        listingsByWatch[id] = nil
        scheduleSave()
    }

    public func update(_ watch: Watch) {
        guard let index = watches.firstIndex(where: { $0.id == watch.id }) else { return }
        watches[index] = watch
        scheduleSave()
    }

    public func updateSettings(_ newValue: MarketSettings) {
        settings = newValue
        scheduleSave()
    }

    // MARK: - Listings

    /// Records whatever is new for this watch and returns just those.
    @discardableResult
    public func record(_ scraped: [ScrapedListing], for watchID: UUID) -> [Listing] {
        let existing = listingsByWatch[watchID] ?? []
        let seenIDs = Set(existing.map(\.id))
        let fresh = newListings(scraped, seenIDs: seenIDs).map {
            Listing(
                id: $0.id,
                watchID: watchID,
                title: $0.title,
                price: $0.price,
                location: $0.location,
                url: $0.url,
                imageURL: $0.imageURL
            )
        }
        guard !fresh.isEmpty else { return [] }

        // Newest first, capped. Dropping from the tail drops the oldest.
        listingsByWatch[watchID] = Array((fresh + existing).prefix(Self.listingsPerWatchCap))
        scheduleSave()
        return fresh
    }

    public func listings(for watchID: UUID) -> [Listing] {
        listingsByWatch[watchID] ?? []
    }

    public func newest(for watchID: UUID, limit: Int) -> [Listing] {
        Array(listings(for: watchID).prefix(limit))
    }

    public func unseenCount(for watchID: UUID) -> Int {
        // `count(where:)` is Swift 6.0; this package is 5.9.
        listings(for: watchID).filter { !$0.seen }.count
    }

    public var totalUnseen: Int {
        watches.reduce(0) { $0 + unseenCount(for: $1.id) }
    }

    public func markSeen(watchID: UUID) {
        guard var existing = listingsByWatch[watchID] else { return }
        for index in existing.indices { existing[index].seen = true }
        listingsByWatch[watchID] = existing
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(MarketDocument.self, named: filename) else {
                return
            }
            watches = document.watches
            settings = document.settings
            listingsByWatch = Dictionary(grouping: document.listings, by: \.watchID)
        } catch {
            // PluginStorage kept a .bak beside the file, so nothing is lost —
            // but the user should know why their watches vanished.
            loadFailureNotice = "Couldn't read your watches. A copy was kept as market.json.bak."
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let document = MarketDocument(
            watches: watches,
            listings: listingsByWatch.values.flatMap { $0 },
            settings: settings
        )
        try? storage.save(document, named: filename)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketStoreTests`
Expected: `** TEST SUCCEEDED **`, 20 tests

Note `testStateSurvivesAReload` calls `saveNow()` explicitly rather than waiting on the debounce — a test that sleeps for a debounce is a slow test and a flaky one.

- [ ] **Step 6: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: Market store with debounced persistence"
```

---

### Task 4: The listing source seam and the poller

Everything that will eventually touch Facebook goes behind `ListingSource` here. Plan 2 writes the real implementation; nothing in this plan does.

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/ListingSource.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Poller/WatchPoller.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/WatchPollerTests.swift`
- Modify: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketTestSupport.swift`

**Interfaces:**
- Consumes: `MarketStore`, `Watch`, `ScrapedListing`.
- Produces: `protocol ListingSource` with `func search(query: String, maxPrice: Int?, location: String, radiusKm: Int) async throws -> [ScrapedListing]`; `enum SearchError: Error { case signedOut, failed(String) }`; `enum PollerState: Equatable { case idle, polling, signedOut, backoff }`; `WatchPoller(store:source:clock:jitter:onFinds:)` with `state: PollerState`, `lastError: String?`, `func tick() async -> [(UUID, Int)]`, `func run()`, `func stop()`. Constants `WatchPoller.minIntervalSeconds = 600`, `maxBackoffSeconds = 7200`, `signInRetrySeconds = 60`.

- [ ] **Step 1: Write the failing test**

Append to `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketTestSupport.swift`:

```swift
@testable import MarketPlugin

/// A `ListingSource` whose answers are scripted, so the poller can be tested
/// without a browser.
@MainActor
final class FakeListingSource: ListingSource {
    struct Call: Equatable {
        let query: String
        let maxPrice: Int?
        let location: String
        let radiusKm: Int
    }

    var results: [ScrapedListing] = []
    var error: SearchError?
    /// When set, only the first call fails; later calls succeed.
    var failFirstCallOnly = false
    private(set) var calls: [Call] = []

    init(results: [ScrapedListing] = []) {
        self.results = results
    }

    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        calls.append(Call(query: query, maxPrice: maxPrice, location: location, radiusKm: radiusKm))
        if let error {
            if failFirstCallOnly { self.error = nil }
            throw error
        }
        return results
    }
}

/// A clock the test moves by hand. No test sleeps.
final class FakeClock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func callAsFunction() -> Date { now }

    func advance(_ seconds: TimeInterval) { now += seconds }
}
```

`Plugins/MarketPlugin/Tests/MarketPluginTests/WatchPollerTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import XCTest

@MainActor
final class WatchPollerTests: XCTestCase {
    private var clock = FakeClock()

    private func makeStore() -> MarketStore {
        let store = MarketStore(storage: MarketFixture.temporaryStorage())
        store.updateSettings(MarketSettings(location: "auckland", radiusKm: 50))
        return store
    }

    private func makePoller(
        store: MarketStore,
        source: FakeListingSource,
        jitter: @escaping (Double, Double) -> Double = { _, _ in 1.0 },
        onFinds: ((UUID, Int) -> Void)? = nil
    ) -> WatchPoller {
        WatchPoller(
            store: store,
            source: source,
            clock: { [clock] in clock.now },
            jitter: jitter,
            onFinds: onFinds
        )
    }

    func testATickSearchesADueWatch() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: 200)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(
            source.calls,
            [.init(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)]
        )
    }

    func testATickReportsTheNewCount() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a"), scraped("b")])
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!

        let results = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.0, watch.id)
        XCTAssertEqual(results.first?.1, 2)
    }

    func testASecondTickReportsNothingNew() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        clock.advance(WatchPoller.minIntervalSeconds * 2)

        XCTAssertTrue(await poller.tick().isEmpty)
    }

    func testAWatchIsNotRecheckedBeforeTheFloor() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        clock.advance(WatchPoller.minIntervalSeconds - 1)
        _ = await poller.tick()

        XCTAssertEqual(source.calls.count, 1)
    }

    func testAPausedWatchIsSkipped() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.paused = true
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertTrue(source.calls.isEmpty)
    }

    func testWatchesArePolledOneAtATimeInOrder() async {
        let store = makeStore()
        let source = FakeListingSource()
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(source.calls.map(\.query), ["first", "second"])
    }

    func testLowSideJitterCannotScheduleBelowTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 10)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source, jitter: { _, _ in 0.8 }).tick()

        let next = store.watches.first!.nextCheckAt
        XCTAssertGreaterThanOrEqual(
            next.timeIntervalSince(clock.now), WatchPoller.minIntervalSeconds
        )
    }

    func testHighSideJitterIsNotFlattenedToTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 10)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source, jitter: { _, _ in 1.2 }).tick()

        let next = store.watches.first!.nextCheckAt
        XCTAssertGreaterThan(next.timeIntervalSince(clock.now), WatchPoller.minIntervalSeconds)
    }

    func testAFailureBacksTheWatchOff() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 1)
        XCTAssertEqual(poller.state, .backoff)
        XCTAssertEqual(poller.lastError, "boom")
    }

    func testBackoffGrowsWithEachFailure() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()
        let first = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)
        clock.advance(first)
        _ = await poller.tick()
        let second = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)

        XCTAssertGreaterThan(second, first)
    }

    func testBackoffIsCapped() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.consecutiveFailures = 50
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        let delay = store.watches.first!.nextCheckAt.timeIntervalSince(clock.now)
        XCTAssertLessThanOrEqual(delay, WatchPoller.maxBackoffSeconds)
    }

    func testASuccessClearsTheFailureCount() async {
        let store = makeStore()
        let source = FakeListingSource()
        var watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        watch.consecutiveFailures = 3
        store.update(watch)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 0)
    }

    func testAFailureOnOneWatchDoesNotBlockTheNext() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        source.failFirstCallOnly = true
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(source.calls.map(\.query), ["first", "second"])
    }

    func testBeingSignedOutStopsTheWholeTick() async {
        // Polling the second watch would only hit the same wall.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)
        let poller = makePoller(store: store, source: source)

        _ = await poller.tick()

        XCTAssertEqual(source.calls.count, 1)
        XCTAssertEqual(poller.state, .signedOut)
    }

    func testBeingSignedOutIsNotCountedAsAFailure() async {
        // It is a human problem, not a flaky scrape — no exponential backoff.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(store.watches.first?.consecutiveFailures, 0)
    }

    func testEveryDueWatchIsPushedPastTheSignInRetry() async {
        // Otherwise the next tick immediately retries a different watch
        // against the same wall.
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "first", maxPrice: nil)
        store.addWatch(query: "second", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        for watch in store.watches {
            XCTAssertGreaterThanOrEqual(
                watch.nextCheckAt.timeIntervalSince(clock.now), WatchPoller.signInRetrySeconds
            )
        }
    }

    func testRecoveringFromSignedOutReturnsToIdle() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .signedOut
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        source.error = nil
        clock.advance(WatchPoller.minIntervalSeconds * 2)
        _ = await poller.tick()

        XCTAssertEqual(poller.state, .idle)
        XCTAssertNil(poller.lastError)
    }

    func testRecoveringFromBackoffReturnsToIdle() async {
        let store = makeStore()
        let source = FakeListingSource()
        source.error = .failed("boom")
        store.addWatch(query: "GoPro", maxPrice: nil)
        let poller = makePoller(store: store, source: source)
        _ = await poller.tick()

        source.error = nil
        clock.advance(WatchPoller.maxBackoffSeconds * 2)
        _ = await poller.tick()

        XCTAssertEqual(poller.state, .idle)
    }

    func testTheFindsCallbackFiresPerWatch() async {
        let store = makeStore()
        let source = FakeListingSource(results: [scraped("a")])
        let watch = store.addWatch(query: "GoPro", maxPrice: nil)!
        var seen: [(UUID, Int)] = []

        _ = await makePoller(store: store, source: source, onFinds: { seen.append(($0, $1)) })
            .tick()

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, watch.id)
        XCTAssertEqual(seen.first?.1, 1)
    }

    func testTheCallbackDoesNotFireWhenNothingIsNew() async {
        let store = makeStore()
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)
        var seen: [(UUID, Int)] = []

        _ = await makePoller(store: store, source: source, onFinds: { seen.append(($0, $1)) })
            .tick()

        XCTAssertTrue(seen.isEmpty)
    }

    func testTheConfiguredIntervalIsHonouredAboveTheFloor() async {
        let store = makeStore()
        store.updateSettings(
            MarketSettings(location: "auckland", radiusKm: 50, pollIntervalMinutes: 60)
        )
        let source = FakeListingSource()
        store.addWatch(query: "GoPro", maxPrice: nil)

        _ = await makePoller(store: store, source: source).tick()

        XCTAssertEqual(
            store.watches.first!.nextCheckAt.timeIntervalSince(clock.now), 3600, accuracy: 0.5
        )
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter WatchPollerTests`
Expected: FAIL — `cannot find 'WatchPoller' in scope`

- [ ] **Step 3: Write the source protocol**

`Session/ListingSource.swift`:

```swift
import Foundation

/// Where listings come from.
///
/// The whole point of this protocol is that nothing above it knows about
/// WKWebView, Facebook, or HTML. Plan 2 implements it against a real webview;
/// every test in this plan uses a fake.
@MainActor
public protocol ListingSource {
    func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing]
}

public enum SearchError: Error, Equatable {
    /// The Facebook session is gone. A human has to sign in; retrying harder
    /// does not help, so this must never be treated as a flaky scrape.
    case signedOut
    /// The search did not complete. Worth retrying later.
    case failed(String)
}
```

- [ ] **Step 4: Write the poller**

`Poller/WatchPoller.swift`:

```swift
import Foundation
import Observation

public enum PollerState: Equatable {
    case idle
    case polling
    case signedOut
    case backoff
}

/// The loop.
///
/// Strictly serial, on purpose: there is one webview behind `ListingSource`,
/// and polling Facebook in parallel from one address is how a session gets
/// killed. Jitter keeps checks off a fixed cadence.
@MainActor
@Observable
public final class WatchPoller {
    public static let minIntervalSeconds: TimeInterval = 600
    public static let maxBackoffSeconds: TimeInterval = 7200
    public static let signInRetrySeconds: TimeInterval = 60

    /// How often the loop wakes to see whether anything is due. Not the poll
    /// interval — that is per watch, and much longer.
    static let tickIntervalSeconds: TimeInterval = 30

    public private(set) var state: PollerState = .idle
    public private(set) var lastError: String?

    private let store: MarketStore
    private let source: ListingSource
    private let clock: () -> Date
    private let jitter: (Double, Double) -> Double
    private let onFinds: ((UUID, Int) -> Void)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        store: MarketStore,
        source: ListingSource,
        clock: @escaping () -> Date = { .now },
        jitter: @escaping (Double, Double) -> Double = { Double.random(in: $0...$1) },
        onFinds: ((UUID, Int) -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.clock = clock
        self.jitter = jitter
        self.onFinds = onFinds
    }

    /// Polls every watch that is due. Returns one pair per watch that found
    /// something new.
    @discardableResult
    public func tick() async -> [(UUID, Int)] {
        let now = clock()
        let due = store.watches.filter { !$0.paused && $0.nextCheckAt <= now }
        guard !due.isEmpty else {
            if state == .polling { state = .idle }
            return []
        }

        state = .polling
        var results: [(UUID, Int)] = []

        for (position, watch) in due.enumerated() {
            do {
                let scraped = try await source.search(
                    query: watch.query,
                    maxPrice: watch.maxPrice,
                    location: watch.location,
                    radiusKm: watch.radiusKm
                )
                let fresh = store.record(scraped, for: watch.id)
                reschedule(watch, after: interval(), failures: 0)
                if !fresh.isEmpty {
                    results.append((watch.id, fresh.count))
                    onFinds?(watch.id, fresh.count)
                }
            } catch SearchError.signedOut {
                // A human problem, not a flaky scrape: no failure count, no
                // backoff, and no point trying the rest — they hit the same
                // wall. Push every watch we have not yet attempted past the
                // retry window, or the next tick just picks a different one.
                state = .signedOut
                lastError = nil
                for pending in due[position...] {
                    reschedule(
                        pending,
                        after: Self.signInRetrySeconds,
                        failures: pending.consecutiveFailures,
                        checked: false
                    )
                }
                return results
            } catch {
                state = .backoff
                lastError = Self.describe(error)
                let failures = watch.consecutiveFailures + 1
                reschedule(watch, after: backoff(failures: failures), failures: failures)
                continue
            }
        }

        if state == .polling {
            state = .idle
            lastError = nil
        }
        return results
    }

    /// Runs `tick()` forever, waking every 30 seconds to see what is due.
    /// Holds only a weak reference, so it returns once the plugin is gone.
    public func run() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Self.tickIntervalSeconds))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - Scheduling

    private func reschedule(
        _ watch: Watch, after seconds: TimeInterval, failures: Int, checked: Bool = true
    ) {
        var updated = watch
        updated.consecutiveFailures = failures
        if checked { updated.lastCheckedAt = clock() }
        updated.nextCheckAt = clock().addingTimeInterval(seconds)
        store.update(updated)
    }

    private func interval() -> TimeInterval {
        let configured = TimeInterval(store.settings.pollIntervalMinutes * 60)
        let base = max(configured, Self.minIntervalSeconds)
        // Clamped after jitter, not before: a 0.8 draw on a floor-length base
        // would otherwise schedule below the floor.
        return max(base * jitter(0.8, 1.2), Self.minIntervalSeconds)
    }

    private func backoff(failures: Int) -> TimeInterval {
        let base = min(Self.minIntervalSeconds * pow(2, Double(failures)), Self.maxBackoffSeconds)
        return min(base * jitter(0.8, 1.2), Self.maxBackoffSeconds)
    }

    private static func describe(_ error: Error) -> String {
        if case SearchError.failed(let message) = error { return message }
        return String(describing: error)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter WatchPollerTests`
Expected: `** TEST SUCCEEDED **`, 21 tests

- [ ] **Step 6: Commit**

```bash
git add Plugins/MarketPlugin
git commit -m "feat: listing source seam and the watch poller"
```

---

### Task 5: The plugin conformance and registration

After this task, Market is a real tab in Perch.

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Market.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Session/StubListingSource.swift`
- Modify: `Perch/PerchApp.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketPluginTests.swift`

**Interfaces:**
- Consumes: `MarketStore`, `WatchPoller`, `ListingSource`, `PerchKit`.
- Produces: `Market: PerchPlugin` with `Market.identifier`, `Market.displayName`, `Market.icon`, `Market.capabilities`, `init(context:)`, `init(context:source:)`, `store`, `poller`. `StubListingSource` conforming to `ListingSource`, returning nothing.

- [ ] **Step 1: Write the failing test**

`Plugins/MarketPlugin/Tests/MarketPluginTests/MarketPluginTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import PerchKit
import XCTest

@MainActor
final class MarketPluginTests: XCTestCase {
    private func makePlugin() -> Market {
        Market(
            context: PluginContext(
                storage: MarketFixture.temporaryStorage(),
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "MarketTests-\(UUID().uuidString)")!,
                    prefix: Market.identifier
                )
            ),
            source: StubListingSource()
        )
    }

    func testItsIdentityIsStable() {
        // Changing this orphans the user's watches on disk.
        XCTAssertEqual(Market.identifier, "org.ahlab.perch.market")
        XCTAssertEqual(Market.displayName, "Market")
        XCTAssertEqual(Market.icon, "binoculars")
    }

    func testItDisclosesNetworkAndNotifications() {
        XCTAssertEqual(Market.capabilities, [.network, .notifications])
    }

    func testTheMenuBarKeepsItsIconWithNothingUnseen() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.menuBarLabel?.systemImage, "binoculars")
        XCTAssertNil(plugin.menuBarLabel?.text)
    }

    func testTheMenuBarShowsTheUnseenCount() {
        let plugin = makePlugin()
        plugin.store.updateSettings(MarketSettings(location: "auckland"))
        let watch = plugin.store.addWatch(query: "GoPro", maxPrice: nil)!
        plugin.store.record([scraped("a"), scraped("b")], for: watch.id)

        XCTAssertEqual(plugin.menuBarLabel?.text, "2")
    }

    func testFlushWritesTheDocument() throws {
        let storage = MarketFixture.temporaryStorage()
        let plugin = Market(
            context: PluginContext(
                storage: storage,
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "MarketTests-\(UUID().uuidString)")!,
                    prefix: Market.identifier
                )
            ),
            source: StubListingSource()
        )
        plugin.store.updateSettings(MarketSettings(location: "auckland"))
        plugin.store.addWatch(query: "GoPro", maxPrice: nil)

        plugin.flush()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storage.url(named: "market.json").path)
        )
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketPluginTests`
Expected: FAIL — `cannot find 'Market' in scope`

- [ ] **Step 3: Write the stub source**

`Session/StubListingSource.swift`:

```swift
import Foundation

/// A `ListingSource` that finds nothing.
///
/// Plan 1 ships this so the tab is real and usable before any Facebook code
/// exists. Plan 2 replaces it with the WKWebView implementation, and this type
/// goes away with it.
@MainActor
public struct StubListingSource: ListingSource {
    public init() {}

    public func search(
        query: String, maxPrice: Int?, location: String, radiusKm: Int
    ) async throws -> [ScrapedListing] {
        []
    }
}
```

- [ ] **Step 4: Write the plugin**

`Market.swift`:

```swift
import Observation
import PerchKit
import SwiftUI

/// Facebook Marketplace searches in the menu bar: type a query and a price
/// cap, and new listings turn up in the panel.
///
/// Declares `.network` because it talks to Facebook, and `.notifications`
/// because it tells you when something turns up.
@MainActor
@Observable
public final class Market: PerchPlugin {
    public static let identifier = "org.ahlab.perch.market"
    public static let displayName = "Market"
    public static let icon = "binoculars"
    public static let capabilities: Set<PluginCapability> = [.network, .notifications]

    public let store: MarketStore
    public let poller: WatchPoller

    public required convenience init(context: PluginContext) {
        self.init(context: context, source: StubListingSource())
    }

    /// The testable initializer. Plan 2 passes the real WKWebView-backed
    /// source here; tests pass a fake.
    public init(context: PluginContext, source: ListingSource) {
        let store = MarketStore(storage: context.storage)
        self.store = store
        poller = WatchPoller(store: store, source: source)
        poller.run()
    }

    public var panel: AnyView {
        AnyView(MarketPanelView(store: store, poller: poller))
    }

    public var settings: AnyView {
        AnyView(MarketSettingsView(store: store))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape,
    /// with the count appearing once there is one.
    public var menuBarLabel: MenuBarLabel? {
        let unseen = store.totalUnseen
        return MenuBarLabel(systemImage: Self.icon, text: unseen > 0 ? "\(unseen)" : nil)
    }

    /// The store debounces its writes; this covers the window between a poll
    /// landing and the process dying.
    public func flush() { store.saveNow() }
}
```

`MarketPanelView` and `MarketSettingsView` do not exist yet — Task 6 writes them. To keep this task compiling on its own, create both as one-line placeholders now and fill them in Task 6:

`Views/MarketPanelView.swift`:

```swift
import SwiftUI

struct MarketPanelView: View {
    let store: MarketStore
    let poller: WatchPoller

    var body: some View {
        Text("Market")
    }
}
```

`Views/MarketSettingsView.swift`:

```swift
import SwiftUI

struct MarketSettingsView: View {
    let store: MarketStore

    var body: some View {
        Text("Market settings")
    }
}
```

- [ ] **Step 5: Register the plugin with the host**

In `Perch/PerchApp.swift`, add the import beside the others:

```swift
import MarketPlugin
```

and add the third entry to `makePlugins()`:

```swift
    private static func makePlugins() -> [any PerchPlugin] {
        [
            MenuDo(context: .perch(MenuDo.identifier)),
            Analytics(context: .perch(Analytics.identifier)),
            Market(context: .perch(Market.identifier)),
        ]
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketPluginTests`
Expected: `** TEST SUCCEEDED **`, 5 tests

- [ ] **Step 7: Verify the tab appears**

Build and run Perch, click the menu bar item, and confirm a third tab labelled **Market** sits beside Tasks and Analytics. It will read "Market" and nothing else — Task 6 fills it in.

```bash
xcodebuild -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' build 2>&1 | tail -5
open build/Debug/Perch.app 2>/dev/null || open ~/Library/Developer/Xcode/DerivedData/Perch-*/Build/Products/Debug/Perch.app
```

Do not mark this step done without seeing the tab.

- [ ] **Step 8: Commit**

```bash
git add Plugins/MarketPlugin Perch/PerchApp.swift
git commit -m "feat: register Market as a third Perch tab"
```

---

### Task 6: The panel and settings views

**Files:**
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/RelativeTime.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/MarketPanelView.swift`
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/MarketSettingsView.swift`
- Create: `Plugins/MarketPlugin/Sources/MarketPlugin/Views/WatchRowView.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/RelativeTimeTests.swift`

**Interfaces:**
- Consumes: `MarketStore`, `WatchPoller`, `Watch`, `Listing`.
- Produces: `RelativeTime.describe(_ date: Date, now: Date) -> String`.

- [ ] **Step 1: Write the failing test**

`Plugins/MarketPlugin/Tests/MarketPluginTests/RelativeTimeTests.swift`:

```swift
import Foundation
@testable import MarketPlugin
import XCTest

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testJustNow() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-5), now: now), "just now")
    }

    func testMinutes() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-300), now: now), "5m ago")
    }

    func testHours() {
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    func testDays() {
        XCTAssertEqual(
            RelativeTime.describe(now.addingTimeInterval(-172_800), now: now), "2d ago"
        )
    }

    func testAFutureDateReadsAsJustNowRatherThanNegative() {
        // Clock skew should not produce "-3m ago".
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(60), now: now), "just now")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter RelativeTimeTests`
Expected: FAIL — `cannot find 'RelativeTime' in scope`

- [ ] **Step 3: Write the helper**

`Views/RelativeTime.swift`:

```swift
import Foundation

/// Short relative times for a panel that is only ~320pt wide.
///
/// `RelativeDateTimeFormatter` produces "5 minutes ago", which wraps. This
/// produces "5m ago", which does not.
enum RelativeTime {
    static func describe(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Plugins/MarketPlugin --filter RelativeTimeTests`
Expected: `** TEST SUCCEEDED **`, 5 tests

- [ ] **Step 5: Write the watch row**

`Views/WatchRowView.swift`:

```swift
import SwiftUI

struct WatchRowView: View {
    let watch: Watch
    let unseenCount: Int
    let newest: [Listing]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(watch.query)
                    .lineLimit(1)
                Spacer()
                if let maxPrice = watch.maxPrice {
                    Text("≤$\(maxPrice)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if unseenCount > 0 {
                    Text("\(unseenCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this watch")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded {
                if newest.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(newest) { listing in
                        Link(destination: listing.url) {
                            HStack(spacing: 4) {
                                Text(listing.price)
                                Text(listing.title).lineLimit(1)
                                Spacer()
                                Text(RelativeTime.describe(listing.firstSeenAt))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let checked = watch.lastCheckedAt {
                Text("checked \(RelativeTime.describe(checked))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Never a blank space: an empty watch says since when it has been empty.
    private var emptyMessage: String {
        watch.lastCheckedAt == nil
            ? "not checked yet"
            : "nothing yet, since \(watch.createdAt.formatted(.dateTime.month().day()))"
    }
}
```

- [ ] **Step 6: Write the panel**

Replace `Views/MarketPanelView.swift`:

```swift
import SwiftUI

struct MarketPanelView: View {
    @Bindable var store: MarketStore
    let poller: WatchPoller

    @State private var query = ""
    @State private var maxPrice = ""
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = store.loadFailureNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            statusLine

            HStack(spacing: 6) {
                TextField("What to watch for", text: $query)
                    .textFieldStyle(.roundedBorder)
                TextField("Max $", text: $maxPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
            }
            .disabled(!store.canAddWatch)
            .onSubmit(addWatch)

            if !store.canAddWatch {
                Text("Set a location in Settings first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.watches.isEmpty {
                Text("Nothing watched yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(store.watches) { watch in
                    Divider()
                    WatchRowView(
                        watch: watch,
                        unseenCount: store.unseenCount(for: watch.id),
                        newest: store.newest(for: watch.id, limit: 3),
                        isExpanded: expanded.contains(watch.id),
                        onToggle: { toggle(watch) },
                        onDelete: { store.deleteWatch(id: watch.id) }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The panel never presents itself as watching when it is not.
    @ViewBuilder
    private var statusLine: some View {
        switch poller.state {
        case .signedOut:
            Label("Sign in to Facebook", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .backoff:
            Text(poller.lastError.map { "Retrying — \($0)" } ?? "Retrying")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle, .polling:
            EmptyView()
        }
    }

    private func addWatch() {
        store.addWatch(query: query, maxPrice: Int(maxPrice))
        query = ""
        maxPrice = ""
    }

    /// Expanding a watch is how you look at it, so that is when it stops
    /// counting as unseen.
    private func toggle(_ watch: Watch) {
        if expanded.contains(watch.id) {
            expanded.remove(watch.id)
        } else {
            expanded.insert(watch.id)
            store.markSeen(watchID: watch.id)
        }
    }
}
```

- [ ] **Step 7: Write the settings pane**

Replace `Views/MarketSettingsView.swift`:

```swift
import SwiftUI

struct MarketSettingsView: View {
    @Bindable var store: MarketStore

    @State private var location = ""
    @State private var radiusKm = 50
    @State private var pollIntervalMinutes = 15
    @State private var notificationsEnabled = true

    var body: some View {
        Form {
            Section {
                TextField("City", text: $location)
                    .onSubmit(apply)
                Text(
                    "Facebook scopes searches to a city. Use the slug from a "
                        + "Marketplace URL — the part after /marketplace/, like “auckland”."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Stepper("Radius: \(radiusKm) km", value: $radiusKm, in: 1...500, step: 10)
                    .onChange(of: radiusKm) { apply() }
            } header: {
                Text("Where to search")
            }

            Section {
                Stepper(
                    "Check every \(pollIntervalMinutes) minutes",
                    value: $pollIntervalMinutes,
                    in: 10...240,
                    step: 5
                )
                .onChange(of: pollIntervalMinutes) { apply() }
                Text("Ten minutes is the floor. Checking harder gets the session blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Notify me about new listings", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { apply() }
            } header: {
                Text("How often")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            location = store.settings.location ?? ""
            radiusKm = store.settings.radiusKm
            pollIntervalMinutes = store.settings.pollIntervalMinutes
            notificationsEnabled = store.settings.notificationsEnabled
        }
    }

    private func apply() {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        store.updateSettings(
            MarketSettings(
                location: trimmed.isEmpty ? nil : trimmed,
                radiusKm: radiusKm,
                pollIntervalMinutes: pollIntervalMinutes,
                notificationsEnabled: notificationsEnabled
            )
        )
    }
}
```

- [ ] **Step 8: Run the whole suite**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: `** TEST SUCCEEDED **`, with the existing Tasks and Analytics tests still passing

- [ ] **Step 9: Verify it works in the app**

Build and run Perch. Then, in order:

1. Open Settings → Market. Set the city to `auckland`. Close Settings.
2. Open the panel's Market tab. The add field should now be enabled.
3. Add a watch: "GoPro Hero 12", max 200. It should appear in the list.
4. Click the row. It expands and reads "not checked yet" or "nothing yet" — the stub source finds nothing, which is correct for Plan 1.
5. Quit Perch and reopen it. The watch should still be there.

Do not mark this step done without doing all five. Step 5 in particular is the one that catches a persistence bug.

- [ ] **Step 10: Commit**

```bash
git add Plugins/MarketPlugin/Sources/MarketPlugin/Views Plugins/MarketPlugin/Tests/MarketPluginTests/RelativeTimeTests.swift
git commit -m "feat: Market panel and settings"
```

---

## What Plan 1 deliberately leaves out

- **Any Facebook code.** `StubListingSource` finds nothing. That is the point: the tab, the store, the scheduling, and the panel are all proven before a single line of scraping exists.
- **The Market window.** The footer button, the full history view, and the sign-in webview are Plan 2. `Market` contributes no `footerActions` yet.
- **Notifications.** `.notifications` is declared so the capability is disclosed in Settings from the start, but nothing posts one until Plan 2 has real finds to post about. The spec's risk about `UNUserNotificationCenter` under an ad-hoc signature is tested there.

## Plan 2

Written once this plan is merged and the tab is real: `FacebookSession` and its `WKWebView`, `extract.js` with fixture tests, the `ListingSource` conformance replacing `StubListingSource`, the Market window with full history and settings, the sign-in flow, and notifications.
