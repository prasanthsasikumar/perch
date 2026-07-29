import PerchKit
import XCTest
@testable import AnalyticsPlugin

@MainActor
final class AnalyticsPluginTests: XCTestCase {
    private func makePlugin() -> Analytics {
        Analytics(
            context: PluginContext(
                storage: PluginStorage(directory: Fixture.temporaryDirectory()),
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "PerchTests-\(UUID().uuidString)")!,
                    prefix: Analytics.identifier
                )
            )
        )
    }

    func testMetadata() {
        XCTAssertEqual(Analytics.identifier, "org.ahlab.perch.analytics")
        XCTAssertEqual(Analytics.displayName, "Analytics")
        XCTAssertEqual(Analytics.icon, "chart.line.uptrend.xyaxis")
    }

    /// The disclosure the Plugins pane shows before the user enables it. This
    /// is the first plugin in Perch that does either of these things.
    func testDeclaresNetworkAndCredentialCapabilities() {
        XCTAssertEqual(Analytics.capabilities, [.network, .credentials])
        XCTAssertEqual(
            Analytics.capabilities.disclosureLines,
            ["Stores an account credential", "Connects to the internet"]
        )
    }

    func testMenuBarLabelIsIconOnlyBeforeAnyData() {
        let plugin = makePlugin()
        XCTAssertEqual(plugin.menuBarLabel?.systemImage, "chart.line.uptrend.xyaxis")
        XCTAssertNil(plugin.menuBarLabel?.text)
    }

    /// Nothing to refresh until there is a credential and something to
    /// refresh, so the footer stays empty rather than offering a dead button.
    func testNoRefreshActionUntilConfigured() {
        XCTAssertTrue(makePlugin().footerActions.isEmpty)
    }
}
