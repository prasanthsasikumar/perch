import PerchKit
import XCTest
@testable import AnalyticsPlugin

/// A canned API, so these tests are about the store and the plugin rather
/// than about PostHog.
private final class CannedAPI: GoogleAnalyticsAPI, @unchecked Sendable {
    let clientEmail = ""
    func stats(for propertyID: String, today: Date) async throws -> PropertyStats {
        PropertyStats(
            currentWeek: PropertyStats.Totals(activeUsers: 9, sessions: 10),
            daily: [PropertyStats.DailyPoint(date: "20261108", activeUsers: 4, sessions: 5)],
            includesEngagement: false
        )
    }
    func breakdown(for propertyID: String, today: Date) async throws -> PropertyBreakdown {
        PropertyBreakdown(totals: PropertyStats.Totals(), sections: [], includesEngagement: false)
    }
    func discoverProperties() async throws -> [AnalyticsProperty] { [] }
}

@MainActor
final class PostHogStoreTests: XCTestCase {
    private func makePostHogStore(
        directory: URL, credentials: InMemoryCredentialStore
    ) -> AnalyticsStore {
        AnalyticsStore(postHogStorage: PluginStorage(directory: directory), credentials: credentials) { _ in CannedAPI() }
    }

    // MARK: - Credentials

    /// The key goes to the credential store — the Keychain in production —
    /// and nowhere near the plugin's cache on disk.
    func testConnectingStoresTheKeyInTheCredentialStoreOnly() throws {
        let directory = PostHogFixture.temporaryDirectory()
        let credentials = InMemoryCredentialStore()
        let store = makePostHogStore(directory: directory, credentials: credentials)

        try store.connectPostHog(region: .eu, projectID: " 12345\n", apiKey: "phx_secretkey9876 ")
        store.setProperties([AnalyticsProperty(id: "a.example", displayName: "a.example")])

        let saved = try JSONDecoder().decode(PostHogCredential.self, from: try XCTUnwrap(credentials.data))
        XCTAssertEqual(saved, PostHogCredential(region: .eu, projectID: "12345", apiKey: "phx_secretkey9876"))
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.postHogCredential?.maskedKey, "phx_…9876")

        let cache = try String(contentsOf: directory.appendingPathComponent("posthog.json"), encoding: .utf8)
        XCTAssertTrue(cache.contains("a.example"))
        XCTAssertFalse(cache.contains("phx_secretkey9876"))
        XCTAssertFalse(cache.contains("12345"))
    }

    func testTheProjectTokenIsRefusedWithoutStoringAnything() {
        let credentials = InMemoryCredentialStore()
        let store = makePostHogStore(directory: PostHogFixture.temporaryDirectory(), credentials: credentials)

        XCTAssertThrowsError(try store.connectPostHog(region: .us, projectID: "1", apiKey: "phc_publictoken")) { error in
            guard case .malformedKey(let detail) = error as? AnalyticsError else { return XCTFail("\(error)") }
            XCTAssertTrue(detail.contains("phx_"))
        }
        XCTAssertNil(credentials.data)
        XCTAssertEqual(credentials.saveCount, 0)
        XCTAssertFalse(store.isConfigured)
    }

    func testANonNumericProjectIDIsRefused() {
        let store = makePostHogStore(directory: PostHogFixture.temporaryDirectory(), credentials: InMemoryCredentialStore())
        XCTAssertThrowsError(try store.connectPostHog(region: .us, projectID: "flowsxr", apiKey: "phx_abcdefgh"))
    }

    func testAStoredConnectionIsReadBackLazily() throws {
        let seeded = try JSONEncoder().encode(PostHogFixture.credential)
        let store = makePostHogStore(
            directory: PostHogFixture.temporaryDirectory(), credentials: InMemoryCredentialStore(seeded: seeded)
        )
        XCTAssertEqual(store.postHogCredential, PostHogFixture.credential)
        XCTAssertTrue(store.isConfigured)
        // PostHog has no service-account address to show.
        XCTAssertNil(store.clientEmail)
    }

    func testRemovingTheKeyClearsTheCredentialStore() throws {
        let credentials = InMemoryCredentialStore()
        let store = makePostHogStore(directory: PostHogFixture.temporaryDirectory(), credentials: credentials)
        try store.connectPostHog(region: .us, projectID: "1", apiKey: "phx_abcdefgh")

        try store.removeCredential()

        XCTAssertNil(credentials.data)
        XCTAssertNil(store.postHogCredential)
        XCTAssertFalse(store.isConfigured)
    }

    /// The GA importer must not write a service-account key into the
    /// PostHog Keychain item.
    func testTheGAImporterRefusesOnThePostHogStore() {
        let credentials = InMemoryCredentialStore()
        let store = makePostHogStore(directory: PostHogFixture.temporaryDirectory(), credentials: credentials)
        XCTAssertThrowsError(try store.importCredential(keyFile: Data("{}".utf8)))
        XCTAssertNil(credentials.data)
    }

    // MARK: - Source choice

    private func makeDefaults() -> PluginDefaults {
        let suiteName = "AnalyticsPluginTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { suite.removePersistentDomain(forName: suiteName) }
        return PluginDefaults(suite: suite, prefix: Analytics.identifier)
    }

    private func makePlugin(directory: URL, defaults: PluginDefaults, postHogCredentials: InMemoryCredentialStore) -> Analytics {
        let storage = PluginStorage(directory: directory)
        return Analytics(
            store: AnalyticsStore(storage: storage, credentials: InMemoryCredentialStore()),
            postHogStore: AnalyticsStore(postHogStorage: storage, credentials: postHogCredentials) { _ in CannedAPI() },
            defaults: defaults
        )
    }

    /// Every install before PostHog was a GA install.
    func testTheSourceDefaultsToGoogleAnalytics() {
        let plugin = makePlugin(
            directory: PostHogFixture.temporaryDirectory(), defaults: makeDefaults(),
            postHogCredentials: InMemoryCredentialStore()
        )
        XCTAssertEqual(plugin.source, .googleAnalytics)
        XCTAssertTrue(plugin.activeStore === plugin.store)
    }

    func testTheSourceChoiceSurvivesARelaunch() {
        let directory = PostHogFixture.temporaryDirectory()
        let defaults = makeDefaults()
        let plugin = makePlugin(directory: directory, defaults: defaults, postHogCredentials: InMemoryCredentialStore())

        plugin.source = .postHog

        let relaunched = makePlugin(directory: directory, defaults: defaults, postHogCredentials: InMemoryCredentialStore())
        XCTAssertEqual(relaunched.source, .postHog)
        XCTAssertTrue(relaunched.activeStore === relaunched.postHogStore)
        XCTAssertEqual(defaults.string(AnalyticsSource.defaultsKey), "postHog")
    }

    /// Each source keeps its own sites and numbers in its own file.
    func testSwitchingSourcesLosesNothing() async throws {
        let directory = PostHogFixture.temporaryDirectory()
        let plugin = makePlugin(directory: directory, defaults: makeDefaults(), postHogCredentials: InMemoryCredentialStore())
        plugin.store.setProperties([AnalyticsProperty(id: "516503233", displayName: "homepage")])

        plugin.source = .postHog
        let postHog = try XCTUnwrap(plugin.postHogStore)
        try postHog.connectPostHog(region: .us, projectID: "1", apiKey: "phx_abcdefgh")
        postHog.setProperties([AnalyticsProperty(id: "a.example", displayName: "a.example")])
        await postHog.refresh()
        XCTAssertEqual(plugin.menuBarLabel?.text, "4")

        plugin.source = .googleAnalytics
        XCTAssertEqual(plugin.activeStore.properties.map(\.id), ["516503233"])
        XCTAssertNil(plugin.menuBarLabel?.text)

        plugin.source = .postHog
        XCTAssertEqual(plugin.activeStore.properties.map(\.id), ["a.example"])
        XCTAssertEqual(plugin.menuBarLabel?.text, "4")

        // And from disk, as after a relaunch.
        let reloaded = AnalyticsStore(postHogStorage: PluginStorage(directory: directory), credentials: InMemoryCredentialStore())
        XCTAssertEqual(reloaded.properties.map(\.id), ["a.example"])
        let reloadedGA = AnalyticsStore(storage: PluginStorage(directory: directory), credentials: InMemoryCredentialStore())
        XCTAssertEqual(reloadedGA.properties.map(\.id), ["516503233"])
    }

    func testTypedDomainsAreReducedToTheHost() {
        XCTAssertEqual(AnalyticsProperty.host(fromTyped: " https://WWW.Example.com/path?q=1 "), "www.example.com")
        XCTAssertEqual(AnalyticsProperty.host(fromTyped: "example.com"), "example.com")
    }
}
