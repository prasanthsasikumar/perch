import PerchKit
import XCTest
@testable import AnalyticsPlugin

@MainActor
final class AnalyticsPluginTests: XCTestCase {
    private let siteA = AnalyticsProperty(id: "111", displayName: "a.example")

    /// Builds a plugin against the testable `Analytics(store:refreshInterval:)`
    /// initializer, never `Analytics(context:)` — that path constructs a real
    /// `KeychainCredentialStore` against the live service name, which on a
    /// developer's own machine can load their actual service-account key.
    /// `credentials` defaults to an in-memory store precisely to avoid that.
    private func makePlugin(
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
        api: StubAnalyticsAPI = StubAnalyticsAPI(),
        refreshInterval: TimeInterval = Analytics.defaultRefreshInterval
    ) -> Analytics {
        let store = AnalyticsStore(
            storage: PluginStorage(directory: Fixture.temporaryDirectory()),
            credentials: credentials,
            apiFactory: { _ in api }
        )
        return Analytics(store: store, refreshInterval: refreshInterval)
    }

    /// A plugin whose store is fully configured — a credential and one
    /// property — so `store.refresh()` actually reaches the API instead of
    /// bailing out early. Needed for the behavioural loop tests below, which
    /// count real calls rather than checking a task pointer.
    private func makeConfiguredPlugin(
        api: StubAnalyticsAPI, refreshInterval: TimeInterval
    ) -> Analytics {
        let credentials = InMemoryCredentialStore(
            seeded: try! ServiceAccount(keyFile: try! Fixture.serviceAccountJSON())
        )
        let plugin = makePlugin(credentials: credentials, api: api, refreshInterval: refreshInterval)
        plugin.store.setProperties([siteA])
        return plugin
    }

    /// Polls `condition` until it is true or `timeout` elapses. Bounded
    /// tightly — 1s default, 5ms between checks — so a real bug (the loop
    /// never calling the API) fails the test promptly rather than hanging.
    private func waitUntil(timeout: TimeInterval = 1.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
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

    func testTheRefreshLoopDoesNotRunUntilTheHostEnablesIt() {
        let plugin = makePlugin()

        XCTAssertFalse(plugin.isRefreshLoopRunning)
    }

    func testEnablingStartsTheRefreshLoop() {
        let plugin = makePlugin()

        plugin.setEnabled(true)

        XCTAssertTrue(plugin.isRefreshLoopRunning)
    }

    /// A behavioural companion to the `isRefreshLoopRunning` check above.
    /// `refreshTask == nil` alone does not prove the loop stopped — delete
    /// `refreshTask?.cancel()` from `stopRefreshing()` and that check still
    /// passes while an orphaned loop keeps calling the API every
    /// `refreshInterval`, which is the exact bug this plugin exists to fix.
    /// This counts real API calls instead, so an orphaned loop shows up as
    /// calls that keep growing after `setEnabled(false)`.
    func testDisablingStopsTheRefreshLoop() async {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let plugin = makeConfiguredPlugin(api: api, refreshInterval: 0.01)

        plugin.setEnabled(true)
        await waitUntil { api.callCount >= 3 }
        plugin.setEnabled(false)
        let countAtDisable = api.callCount

        // Bounded, not blind: gives a still-running loop a real chance to
        // make another call, then confirms it did not. 0.2s against a 0.01s
        // refresh interval is twenty cycles' worth of headroom.
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertGreaterThanOrEqual(countAtDisable, 3)
        XCTAssertEqual(api.callCount, countAtDisable)
    }

    /// There was no Analytics equivalent of Market's double-enable test.
    /// `startRefreshing()` already cancels any previous task before starting
    /// a new one; this pins that behaviourally rather than trusting it stays
    /// true, the same way `testDisablingStopsTheRefreshLoop` does for the
    /// simple stop case.
    func testEnablingTwiceDoesNotLeaveTwoRefreshLoopsRunning() async {
        let api = StubAnalyticsAPI(results: ["111": .success(Fixture.stats())])
        let plugin = makeConfiguredPlugin(api: api, refreshInterval: 0.01)

        plugin.setEnabled(true)
        plugin.setEnabled(true) // The double-enable under test.
        await waitUntil { api.callCount >= 3 }
        plugin.setEnabled(false)
        let countAtDisable = api.callCount

        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertGreaterThanOrEqual(countAtDisable, 3)
        XCTAssertEqual(api.callCount, countAtDisable)
    }
}
