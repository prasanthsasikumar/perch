@testable import InternetPlugin
import PerchKit
import XCTest

@MainActor
final class InternetPluginTests: XCTestCase {
    private var storage: PluginStorage!
    private var watcher: FakePathWatcher!
    private var source: FakeProbeSource!
    private var plugin: Internet!

    override func setUp() {
        super.setUp()
        storage = makeTemporaryStorage()
        watcher = FakePathWatcher()
        source = FakeProbeSource()
        plugin = Internet(
            context: PluginContext(storage: storage, defaults: PluginDefaults(prefix: "test.\(UUID())")),
            source: source,
            speedTester: FakeSpeedTester(),
            pathWatcher: watcher
        )
    }

    override func tearDown() {
        plugin.setEnabled(false)
        try? FileManager.default.removeItem(at: storage.directory)
        super.tearDown()
    }

    func testNothingRunsUntilEnabled() {
        XCTAssertFalse(plugin.isCheckLoopRunning)
        XCTAssertFalse(watcher.isRunning)
        XCTAssertEqual(source.calls, 0)
    }

    func testEnablingStartsAndDisablingStopsEverything() {
        plugin.setEnabled(true)
        XCTAssertTrue(plugin.isCheckLoopRunning)
        XCTAssertTrue(watcher.isRunning)

        plugin.setEnabled(false)
        XCTAssertFalse(plugin.isCheckLoopRunning)
        XCTAssertFalse(watcher.isRunning)
    }

    func testMenuBarShowsLatencyWhenHealthy() async {
        await plugin.store.pathChanged(wifi)
        await plugin.store.check()
        XCTAssertEqual(plugin.menuBarLabel, MenuBarLabel(systemImage: "wifi", text: "20 ms"))
    }

    func testMenuBarDropsTheNumberWhenOffline() async {
        source.setAll(.failed)
        await plugin.store.check()
        XCTAssertEqual(plugin.menuBarLabel, MenuBarLabel(systemImage: "wifi.slash", text: nil))
    }
}
