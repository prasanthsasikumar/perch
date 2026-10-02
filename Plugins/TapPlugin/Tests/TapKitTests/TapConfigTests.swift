@testable import TapKit
import XCTest

final class TapConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> TapConfig {
        try JSONDecoder().decode(TapConfig.self, from: Data(json.utf8))
    }

    func testEmptyFileIsTheDefault() throws {
        XCTAssertEqual(try decode("{}"), .default)
    }

    func testMissingKeysKeepTheRest() throws {
        let config = try decode(#"{"sensitivity": 0.3, "layout": "sides"}"#)
        XCTAssertEqual(config.sensitivity, 0.3)
        XCTAssertEqual(config.layout, .sides)
        XCTAssertEqual(config.slots, TapConfig.default.slots)
    }

    func testUnknownValuesFallBack() throws {
        let config = try decode(#"{"soundPack": "Kazoo", "layout": "diagonal"}"#)
        XCTAssertEqual(config.soundPack, .drumKit)
        XCTAssertEqual(config.layout, .knock)
    }

    func testAnIncompleteMapIsReplaced() throws {
        let config = try decode(#"{"slots": [{"side": "left", "tapCount": 1, "actionType": "save", "parameter": ""}]}"#)
        XCTAssertEqual(config.slots, TapConfig.default.slots)
    }

    func testRoundTrip() throws {
        var config = TapConfig.default
        config.applyPreset(.media)
        config.soundPack = .space
        config.sideBias = -0.002
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(TapConfig.self, from: data), config)
    }

    func testPresetsAreRecognised() {
        var config = TapConfig.default
        XCTAssertEqual(config.currentPreset, .daily)
        config.applyPreset(.coding)
        XCTAssertEqual(config.currentPreset, .coding)
        config.slots[0].actionType = .redo
        XCTAssertNil(config.currentPreset)
    }

    func testEveryPresetFillsAllSixCells() {
        for preset in GesturePreset.allCases {
            XCTAssertEqual(Set(preset.slots.map(\.id)).count, 6, preset.title)
        }
        XCTAssertEqual(GesturePreset.daily.knockLine, "Copy · Paste · Undo")
    }

    func testAnywhereUsesTheLeftActionsWhicheverSide() {
        var config = TapConfig.default
        config.appRules = []
        XCTAssertEqual(config.resolvedSlot(side: .right, tapCount: 2, bundleID: nil)?.actionType, .paste)
    }

    func testSidesUseEachSidesActions() {
        var config = TapConfig.default
        config.appRules = []
        config.layout = .sides
        XCTAssertEqual(config.resolvedSlot(side: .right, tapCount: 2, bundleID: nil)?.actionType, .screenshot)
    }

    func testAppRulesOverrideOnlyWhatTheySet() {
        let config = TapConfig.default
        XCTAssertEqual(config.resolvedSlot(side: .left, tapCount: 1, bundleID: "com.anthropic.claudefordesktop")?.actionType, .aiAccept)
        // Claude's rule says nothing about three knocks, so the global one stands.
        XCTAssertEqual(config.resolvedSlot(side: .left, tapCount: 3, bundleID: "com.anthropic.claudefordesktop")?.actionType, .undo)
    }

    func testADisabledRuleIsIgnored() {
        var config = TapConfig.default
        config.appRules[0].enabled = false
        XCTAssertEqual(config.resolvedSlot(side: .left, tapCount: 1, bundleID: config.appRules[0].bundleID)?.actionType, .copy)
    }

    func testResetKeepsOnboarding() {
        var config = TapConfig.default
        config.hasCompletedOnboarding = true
        config.sensitivity = 0.1
        let reset = config.reset()
        XCTAssertTrue(reset.hasCompletedOnboarding)
        XCTAssertEqual(reset.sensitivity, TapConfig.default.sensitivity)
    }

    func testCalibration() throws {
        let straight = try XCTUnwrap(TapConfig.calibration(leftPeaks: [-0.01, -0.012], rightPeaks: [0.008, 0.01]))
        XCTAssertFalse(straight.invertSides)
        XCTAssertEqual(straight.sideBias, -(-0.011 + 0.009) / 2, accuracy: 1e-9)

        let mirrored = try XCTUnwrap(TapConfig.calibration(leftPeaks: [0.01], rightPeaks: [-0.01]))
        XCTAssertTrue(mirrored.invertSides)

        XCTAssertNil(TapConfig.calibration(leftPeaks: [], rightPeaks: [0.01]))
    }

    func testStatsRollOverAtMidnight() {
        var stats = GestureStats()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        stats.record(tapCount: 2, on: day)
        stats.record(tapCount: 1, on: day)
        XCTAssertEqual(stats.today(day), 2)
        XCTAssertEqual(stats.tapsDetected, 3)

        let nextDay = day.addingTimeInterval(86_400)
        XCTAssertEqual(stats.today(nextDay), 0)
        stats.record(tapCount: 3, on: nextDay)
        XCTAssertEqual(stats.today(nextDay), 1)
        XCTAssertEqual(stats.gesturesFired, 3)
    }

    /// One sound for each side and knock count.
    func testSoundPacksHaveSixSounds() {
        for pack in SoundPack.allCases {
            XCTAssertEqual(Set(pack.sounds).count, 6, pack.rawValue)
        }
    }
}
