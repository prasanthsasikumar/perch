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
