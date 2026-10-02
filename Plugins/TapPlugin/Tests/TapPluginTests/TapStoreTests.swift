import PerchKit
import TapKit
@testable import TapPlugin
import XCTest

/// Records what the store asks of the companion, and lets a test play the
/// companion's part.
@MainActor
final class FakeLink: CompanionLink {
    var onStatus: ((TapStatus) -> Void)?
    var onLaunchFailure: ((String) -> Void)?
    private(set) var launches: [URL] = []
    private(set) var sent: [TapCommand] = []

    func launch(configURL: URL) { launches.append(configURL) }
    func send(_ command: TapCommand) { sent.append(command) }

    func reply(_ configure: (inout TapStatus) -> Void = { _ in }) {
        var status = TapStatus()
        status.source = .spu
        configure(&status)
        onStatus?(status)
    }
}

@MainActor
final class TapStoreTests: XCTestCase {
    private var directory: URL!
    private var link: FakeLink!
    private var now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        link = FakeLink()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> TapStore {
        TapStore(storage: PluginStorage(directory: directory), link: link, clock: { [unowned self] in now })
    }

    private func savedConfig() throws -> TapConfig? {
        try PluginStorage(directory: directory).load(TapConfig.self, named: TapStore.filename)
    }

    func testEnablingWritesSettingsThenStartsTheCompanion() throws {
        let store = makeStore()
        store.setEnabled(true)
        XCTAssertNotNil(try savedConfig())
        XCTAssertEqual(link.launches, [store.configURL])
        XCTAssertEqual(store.companion, .starting)
        store.setEnabled(false)
    }

    func testAStatusMeansRunning() {
        let store = makeStore()
        store.setEnabled(true)
        link.reply { $0.isStreaming = true }
        XCTAssertEqual(store.companion, .running)
        XCTAssertTrue(store.isListening)
        store.setEnabled(false)
    }

    func testDisablingQuitsAndForgets() {
        let store = makeStore()
        store.setEnabled(true)
        link.reply()
        store.setEnabled(false)
        XCTAssertEqual(link.sent.last, .quit)
        XCTAssertEqual(store.companion, .off)
        XCTAssertNil(store.status)

        // A late status from the companion on its way out changes nothing.
        link.reply()
        XCTAssertNil(store.status)
    }

    func testEditsAreSavedAndReloaded() throws {
        let store = makeStore()
        store.setEnabled(true)
        store.config.sensitivity = 0.2
        store.saveNow()
        XCTAssertEqual(try savedConfig()?.sensitivity, 0.2)
        XCTAssertEqual(link.sent.last, .reload)
        store.setEnabled(false)
    }

    func testEditsAreSavedAfterAPause() throws {
        let store = makeStore()
        store.config.sensitivity = 0.4
        let saved = expectation(description: "saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { saved.fulfill() }
        wait(for: [saved], timeout: 2)
        XCTAssertEqual(try savedConfig()?.sensitivity, 0.4)
    }

    func testSettingsSurviveARelaunch() {
        let first = makeStore()
        first.applyPreset(.media)
        first.saveNow()
        XCTAssertEqual(makeStore().config.currentPreset, .media)
    }

    func testUnreadableSettingsAreResetWithANotice() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: directory.appendingPathComponent(TapStore.filename))
        let store = makeStore()
        XCTAssertEqual(store.config, .default)
        XCTAssertNotNil(store.loadFailureNotice)
    }

    func testOnlyANewKnockCounts() {
        let store = makeStore()
        store.setEnabled(true)
        let knock = DetectedGesture(side: .left, tapCount: 2, timestamp: 1, peakMagnitude: 0.3, peakX: 0.01)
        link.reply { $0.gestureSequence = 1; $0.lastGesture = knock }
        XCTAssertEqual(store.gestureToken, 1)
        link.reply { $0.gestureSequence = 1; $0.lastGesture = knock }
        XCTAssertEqual(store.gestureToken, 1, "a heartbeat repeating the last knock is not a new one")
        link.reply { $0.gestureSequence = 2; $0.lastGesture = knock }
        XCTAssertEqual(store.gestureToken, 2)
        store.setEnabled(false)
    }

    func testAQuietCompanionIsRestarted() {
        let store = makeStore()
        store.setEnabled(true)
        link.reply()
        now += TapLink.heartbeatTimeout - 1
        store.tick()
        XCTAssertEqual(link.launches.count, 1)

        now += 2
        store.tick()
        XCTAssertEqual(store.companion, .notResponding)
        XCTAssertEqual(link.launches.count, 2)

        // The new one gets its own grace period.
        now += 1
        store.tick()
        XCTAssertEqual(link.launches.count, 2)

        link.reply()
        XCTAssertEqual(store.companion, .running)
        store.setEnabled(false)
    }

    func testACompanionThatNeverAnswersIsRetried() {
        let store = makeStore()
        store.setEnabled(true)
        now += TapLink.heartbeatTimeout + 1
        store.tick()
        XCTAssertEqual(store.companion, .notResponding)
        XCTAssertEqual(link.launches.count, 2)
        store.setEnabled(false)
    }

    func testALaunchFailureWaitsForTheUser() {
        let store = makeStore()
        store.setEnabled(true)
        link.onLaunchFailure?("gone")
        XCTAssertEqual(store.companion, .failed("gone"))
        now += 60
        store.tick()
        XCTAssertEqual(link.launches.count, 1)

        store.retry()
        XCTAssertEqual(link.launches.count, 2)
        XCTAssertEqual(store.companion, .starting)
        store.setEnabled(false)
    }

    func testLiveDataIsLeasedWhileWatched() {
        let store = makeStore()
        store.setEnabled(true)
        link.reply()
        store.beginLive()
        XCTAssertEqual(link.sent.last, .live)

        let before = link.sent.count
        store.tick()
        XCTAssertEqual(link.sent.count, before + 1)
        XCTAssertEqual(link.sent.last, .live)

        store.endLive()
        store.tick()
        XCTAssertEqual(link.sent.count, before + 1, "no renewals once nobody is watching")
        store.setEnabled(false)
    }

    func testTestingSavesFirst() throws {
        let store = makeStore()
        store.setEnabled(true)
        var slot = store.slots(for: .left)[1]
        slot.actionType = .openURL
        slot.parameter = "example.com"
        store.updateSlot(slot)
        store.test(slot)
        XCTAssertEqual(try savedConfig()?.slot(side: .left, tapCount: 2)?.parameter, "example.com")
        XCTAssertEqual(Array(link.sent.suffix(2)), [.reload, .test(.left, 2)])
        store.setEnabled(false)
    }

    func testAppRules() {
        let store = makeStore()
        let id = store.addRule(bundleID: "com.example.app", appName: "Example")
        XCTAssertEqual(store.addRule(bundleID: "com.example.app", appName: "Example"), id, "one rule per app")

        store.setOverride(.save, side: .left, tapCount: 1, inRule: id)
        store.setOverride(.copy, side: .left, tapCount: 1, inRule: id)
        XCTAssertEqual(store.config.resolvedSlot(side: .left, tapCount: 1, bundleID: "com.example.app")?.actionType, .copy)

        store.setOverride(nil, side: .left, tapCount: 1, inRule: id)
        XCTAssertEqual(store.config.appRules.first { $0.id == id }?.slots, [])

        store.removeRule(id)
        XCTAssertFalse(store.config.appRules.contains { $0.id == id })
    }

    func testCalibrationStartsFromRawReadings() {
        let store = makeStore()
        store.setEnabled(true)
        store.config.invertSides = true
        store.config.sideBias = 0.01
        store.beginCalibration()
        XCTAssertFalse(store.config.invertSides)
        XCTAssertEqual(store.config.sideBias, 0)
        XCTAssertEqual(link.sent.last, .start, "the sensor has to be on to calibrate")

        XCTAssertEqual(store.commitCalibration(leftPeaks: [0.01], rightPeaks: [-0.01]), true)
        XCTAssertTrue(store.config.invertSides)
        store.setEnabled(false)
    }

    func testOnboarding() {
        let store = makeStore()
        store.setEnabled(true)
        store.completeOnboarding()
        XCTAssertTrue(store.config.hasCompletedOnboarding)
        store.replayOnboarding()
        XCTAssertFalse(store.config.hasCompletedOnboarding)

        store.config.hasCompletedOnboarding = true
        store.config.sensitivity = 0.1
        store.resetSettings()
        XCTAssertTrue(store.config.hasCompletedOnboarding, "reset keeps setup done")
        XCTAssertEqual(store.config.sensitivity, TapConfig.default.sensitivity)
        store.setEnabled(false)
    }
}

@MainActor
final class TapPluginTests: XCTestCase {
    func testMenuBarFollowsTheSensor() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = FakeLink()
        let tap = Tap(
            context: PluginContext(
                storage: PluginStorage(directory: directory),
                defaults: PluginDefaults(suite: UserDefaults(suiteName: UUID().uuidString)!, prefix: "test")
            ),
            link: link
        )
        tap.setEnabled(true)
        XCTAssertEqual(tap.menuBarLabel?.systemImage, "hand.tap")
        link.reply { $0.isStreaming = true }
        XCTAssertEqual(tap.menuBarLabel?.systemImage, "hand.tap.fill")
        link.reply { $0.source = .unavailable }
        XCTAssertEqual(tap.menuBarLabel?.systemImage, "exclamationmark.triangle")
        tap.setEnabled(false)
        XCTAssertEqual(Tap.capabilities, [.accessibility])
    }
}

/// The companion works out where the settings are without being told, so
/// its idea of the path has to match where Perch's storage puts them.
final class ConfigLocationTests: XCTestCase {
    func testCompanionLooksWherePerchWrites() {
        let home = URL(fileURLWithPath: "/Users/me")
        let companionView = TapLink.configURL(home: home, hostBundleIdentifier: "org.ahlab.Perch")
        XCTAssertEqual(
            companionView.path,
            "/Users/me/Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/org.ahlab.perch.tap/tap.json"
        )

        // Inside the sandbox, Application Support is the container's; the
        // rest of the path is PluginContext's own layout.
        let perchView = PluginContext.standard(appName: "Perch", identifier: Tap.identifier)
            .storage.url(named: TapStore.filename)
        let suffix = "Application Support/Perch/Plugins/org.ahlab.perch.tap/tap.json"
        XCTAssertTrue(perchView.path.hasSuffix(suffix), perchView.path)
        XCTAssertTrue(companionView.path.hasSuffix(suffix))
    }

    func testCompanionFindsItsPerch() {
        let companion = URL(fileURLWithPath: "/Applications/Perch.app/Contents/Helpers/PerchTap.app")
        XCTAssertEqual(TapLink.hostURL(ofCompanionAt: companion).path, "/Applications/Perch.app")
    }
}
