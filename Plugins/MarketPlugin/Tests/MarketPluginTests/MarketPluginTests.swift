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

    func testThePollerDoesNotRunUntilTheHostEnablesIt() {
        // A disabled plugin that started polling in init would fire one real
        // search at every launch before the registry could stop it.
        let plugin = makePlugin()

        XCTAssertFalse(plugin.poller.isRunning)
    }

    func testEnablingStartsThePoller() {
        let plugin = makePlugin()

        plugin.setEnabled(true)

        XCTAssertTrue(plugin.poller.isRunning)
    }

    func testDisablingStopsThePoller() {
        let plugin = makePlugin()
        plugin.setEnabled(true)

        plugin.setEnabled(false)

        XCTAssertFalse(plugin.poller.isRunning)
    }

    func testEnablingTwiceDoesNotLeaveTwoLoopsRunning() {
        let plugin = makePlugin()

        plugin.setEnabled(true)
        plugin.setEnabled(true)
        plugin.setEnabled(false)

        XCTAssertFalse(plugin.poller.isRunning)
    }
}
