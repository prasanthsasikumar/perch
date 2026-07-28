import Observation
import PerchKit
@testable import Perch
import SwiftUI
import XCTest

@MainActor
@Observable
private final class AlphaPlugin: PerchPlugin {
    static let identifier = "alpha"
    static let displayName = "Alpha"
    static let icon = "a.circle"
    static let capabilities: Set<PluginCapability> = []
    required init(context: PluginContext) {}
    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
@Observable
private final class BetaPlugin: PerchPlugin {
    static let identifier = "beta"
    static let displayName = "Beta"
    static let icon = "b.circle"
    static let capabilities: Set<PluginCapability> = [.network]
    required init(context: PluginContext) {}
    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
final class PluginRegistryTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A throwaway context — these stubs never touch storage, and tests have no
    /// business writing into the real Application Support directory.
    private func makePlugins() -> [any PerchPlugin] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        let context = PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(suite: suite, prefix: "stub")
        )
        return [AlphaPlugin(context: context), BetaPlugin(context: context)]
    }

    private func makeRegistry() -> PluginRegistry {
        PluginRegistry(plugins: makePlugins(), defaults: suite)
    }

    func testEverythingIsEnabledByDefault() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha", "beta"])
    }

    func testFirstEnabledIsActiveAndPrimaryByDefault() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.active?.id, "alpha")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testEntryCarriesMetadataFromThePlugin() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.entries.map(\.displayName), ["Alpha", "Beta"])
        XCTAssertEqual(registry.entries.map(\.icon), ["a.circle", "b.circle"])
        XCTAssertEqual(registry.entries[1].capabilities, [.network])
    }

    func testDisablingAPluginRemovesItFromEnabled() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha"])
        XCTAssertFalse(registry.isEnabled("beta"))
    }

    func testDisablingTheActivePluginMovesActiveToTheFirstRemaining() {
        let registry = makeRegistry()
        registry.activeID = "beta"
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.active?.id, "alpha")
    }

    func testDisablingThePrimaryPluginMovesPrimaryToTheFirstRemaining() {
        let registry = makeRegistry()
        registry.primaryID = "beta"
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testDisablingEverythingLeavesNoActiveOrPrimary() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "alpha")
        registry.setEnabled(false, for: "beta")
        XCTAssertNil(registry.active)
        XCTAssertNil(registry.primary)
    }

    func testSelectionsPersistAcrossInstances() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "alpha")
        registry.primaryID = "beta"
        registry.activeID = "beta"

        let reloaded = makeRegistry()
        XCTAssertEqual(reloaded.enabled.map(\.id), ["beta"])
        XCTAssertEqual(reloaded.primary?.id, "beta")
        XCTAssertEqual(reloaded.active?.id, "beta")
    }

    func testAPersistedIDForAPluginThatNoLongerExistsIsIgnored() {
        suite.set(["alpha", "gamma"], forKey: "enabledPluginIDs")
        suite.set("gamma", forKey: "activePluginID")
        suite.set("gamma", forKey: "primaryPluginID")

        let registry = makeRegistry()
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha"])
        XCTAssertEqual(registry.active?.id, "alpha")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testTabStripIsHiddenUntilASecondPluginIsEnabled() {
        let registry = makeRegistry()
        XCTAssertTrue(registry.showsTabStrip)
        registry.setEnabled(false, for: "beta")
        XCTAssertFalse(registry.showsTabStrip)
    }
}
