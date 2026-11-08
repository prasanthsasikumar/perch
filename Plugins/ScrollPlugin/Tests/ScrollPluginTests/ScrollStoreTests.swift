import PerchKit
import ScrollKit
@testable import ScrollPlugin
import XCTest

/// Records what the store asks of the companion, and lets a test play the
/// companion's part.
@MainActor
final class FakeScrollLink: ScrollCompanionLink {
    var onStatus: ((ScrollStatus) -> Void)?
    var onLaunchFailure: ((String) -> Void)?
    private(set) var launches = 0
    private(set) var sent: [ScrollCommand] = []

    func launch() { launches += 1 }
    func send(_ command: ScrollCommand) { sent.append(command) }

    func reply(_ configure: (inout ScrollStatus) -> Void = { _ in }) {
        var status = ScrollStatus()
        configure(&status)
        onStatus?(status)
    }
}

@MainActor
final class ScrollStoreTests: XCTestCase {
    private var directory: URL!
    private var link: FakeScrollLink!
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var running: [String] = []
    private var opened: [URL] = []

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        link = FakeScrollLink()
        running = []
        opened = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(setUp: Bool = false) throws -> ScrollStore {
        if setUp {
            var settings = ScrollSettings.default
            settings.hasCompletedSetup = true
            try PluginStorage(directory: directory).save(settings, named: ScrollStore.filename)
        }
        return ScrollStore(
            storage: PluginStorage(directory: directory),
            link: link,
            clock: { [unowned self] in now },
            runningBundleIdentifiers: { [unowned self] in running },
            openURL: { [unowned self] in opened.append($0) }
        )
    }

    private func savedSettings() throws -> ScrollSettings? {
        try PluginStorage(directory: directory).load(ScrollSettings.self, named: ScrollStore.filename)
    }

    /// Upgraders get the plugin switched on. Nothing runs until they open it.
    func testEnablingBeforeSetupStartsNothing() throws {
        let store = try makeStore()
        store.setEnabled(true)
        XCTAssertEqual(link.launches, 0)
        XCTAssertEqual(store.companion, .off)
        store.setEnabled(false)
    }

    func testSetupStartsTheCompanionSoItCanAskForAccessibility() throws {
        let store = try makeStore()
        store.setEnabled(true)
        store.beginSetup()
        XCTAssertEqual(link.launches, 1)
        XCTAssertEqual(store.companion, .starting)
        store.setEnabled(false)
    }

    func testEnablingOnceSetUpWritesSettingsThenStartsTheCompanion() throws {
        let store = try makeStore(setUp: true)
        store.setEnabled(true)
        XCTAssertNotNil(try savedSettings())
        XCTAssertEqual(link.launches, 1)
        store.setEnabled(false)
    }

    func testDisablingQuitsTheCompanion() throws {
        let store = try makeStore(setUp: true)
        store.setEnabled(true)
        link.reply { $0.isTrusted = true; $0.isTapActive = true }
        store.setEnabled(false)
        XCTAssertEqual(link.sent.last, .quit)
        XCTAssertEqual(store.companion, .off)
        XCTAssertNil(store.status)
    }

    func testFinishingSetupIsSavedAndTheCompanionToldToReread() throws {
        let store = try makeStore()
        store.setEnabled(true)
        store.beginSetup()
        store.completeSetup()
        XCTAssertEqual(try savedSettings()?.hasCompletedSetup, true)
        XCTAssertEqual(link.sent.last, .reload)
        XCTAssertEqual(link.launches, 1)
        store.setEnabled(false)
    }

    /// The companion picks up a change without a restart.
    func testAChangedSettingIsSavedAndReloaded() throws {
        let store = try makeStore(setUp: true)
        store.setEnabled(true)
        store.settings.reverseTrackpad = true
        store.saveNow()
        XCTAssertEqual(try savedSettings()?.reverseTrackpad, true)
        XCTAssertEqual(link.sent.last, .reload)
        XCTAssertEqual(link.launches, 1)
        store.setEnabled(false)
    }

    func testStates() throws {
        let store = try makeStore(setUp: true)
        XCTAssertEqual(store.state, .helperNotRunning)
        store.setEnabled(true)
        XCTAssertEqual(store.state, .starting)
        link.reply { $0.isTrusted = false }
        XCTAssertEqual(store.state, .needsAccessibility)
        link.reply { $0.isTrusted = true; $0.isTapActive = true }
        XCTAssertEqual(store.state, .active)
        store.settings.isOn = false
        XCTAssertEqual(store.state, .paused)
        store.setEnabled(false)
    }

    func testASilentCompanionIsRestarted() throws {
        let store = try makeStore(setUp: true)
        store.setEnabled(true)
        link.reply { $0.isTrusted = true }
        now += ScrollLink.heartbeatTimeout + 1
        store.tick()
        XCTAssertEqual(store.companion, .notResponding)
        XCTAssertEqual(store.state, .helperNotRunning)
        XCTAssertEqual(link.launches, 2)
        store.setEnabled(false)
    }

    func testAccessibilityIsAskedForByTheCompanionWhenItIsRunning() throws {
        let store = try makeStore(setUp: true)
        store.setEnabled(true)
        store.requestAccessibility()
        XCTAssertEqual(opened, [ScrollLink.accessibilitySettingsURL])
        link.reply()
        store.requestAccessibility()
        XCTAssertEqual(link.sent.last, .requestAccessibility)
        XCTAssertEqual(opened.count, 1)
        store.setEnabled(false)
    }

    func testScrollReverserIsNoticed() throws {
        let store = try makeStore()
        store.refreshConflicts()
        XCTAssertFalse(store.isScrollReverserRunning)
        running = ["com.apple.finder", ScrollLink.scrollReverserBundleIdentifier]
        store.refreshConflicts()
        XCTAssertTrue(store.isScrollReverserRunning)
    }

    func testThePluginDeclaresInput() {
        XCTAssertEqual(Scroll.capabilities, [.input])
        XCTAssertEqual(Scroll.identifier, "org.ahlab.perch.scroll")
    }
}
