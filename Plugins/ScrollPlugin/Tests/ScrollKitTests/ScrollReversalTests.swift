import CoreGraphics
import ScrollKit
import XCTest

/// Stands in for a scroll event, including the part that makes the order of
/// writes matter: setting a line delta recomputes that axis's other two.
final class FakeScrollEvent: ScrollFieldAccess {
    var values: [ScrollField: Double]
    private(set) var writes: [ScrollField] = []

    init(_ values: [ScrollField: Double]) { self.values = values }

    func value(of field: ScrollField) -> Double { values[field] ?? 0 }

    func setValue(_ value: Double, of field: ScrollField) {
        writes.append(field)
        values[field] = value
        switch field {
        case .lineVertical:
            values[.pointVertical] = value * 8
            values[.fixedVertical] = value
        case .lineHorizontal:
            values[.pointHorizontal] = value * 8
            values[.fixedHorizontal] = value
        default:
            break
        }
    }
}

final class ScrollClassifierTests: XCTestCase {
    func testAWheelClickHasNoPhaseAndIsAMouse() {
        XCTAssertEqual(ScrollClassifier.device(scrollPhase: 0, momentumPhase: 0), .mouse)
    }

    /// May-begin, began, changed and ended, as NSEvent.Phase raw values.
    func testAnyGesturePhaseIsATrackpad() {
        for phase: Int64 in [128, 1, 2, 4, 8] {
            XCTAssertEqual(ScrollClassifier.device(scrollPhase: phase, momentumPhase: 0), .trackpad, "phase \(phase)")
        }
    }

    /// The coast after the fingers lift has no gesture phase, only momentum.
    func testMomentumAloneIsATrackpad() {
        for phase: Int64 in [1, 2, 4] {
            XCTAssertEqual(ScrollClassifier.device(scrollPhase: 0, momentumPhase: phase), .trackpad, "momentum \(phase)")
        }
    }
}

final class ScrollSettingsTests: XCTestCase {
    private func ready(_ configure: (inout ScrollSettings) -> Void = { _ in }) -> ScrollSettings {
        var settings = ScrollSettings.default
        settings.hasCompletedSetup = true
        configure(&settings)
        return settings
    }

    func testDefaultsReverseTheMouseOnBothAxesAndLeaveTheTrackpad() {
        let settings = ScrollSettings.default
        XCTAssertTrue(settings.isOn)
        XCTAssertTrue(settings.reverseMouse)
        XCTAssertFalse(settings.reverseTrackpad)
        XCTAssertTrue(settings.reverseVertical)
        XCTAssertTrue(settings.reverseHorizontal)
        XCTAssertFalse(settings.hasCompletedSetup)
    }

    func testOnceSetUpTheDefaultsReverseOnlyTheMouse() {
        let settings = ready()
        XCTAssertEqual(settings.axesToReverse(for: .mouse), .both)
        XCTAssertEqual(settings.axesToReverse(for: .trackpad), [])
    }

    /// New plugins arrive switched on for upgraders; nothing changes until
    /// the setup is done.
    func testNothingIsReversedBeforeSetup() {
        let settings = ScrollSettings.default
        XCTAssertFalse(settings.isReversing)
        XCTAssertEqual(settings.axesToReverse(for: .mouse), [])
    }

    func testTheMasterSwitchStopsEverything() {
        let settings = ready { $0.isOn = false; $0.reverseTrackpad = true }
        XCTAssertFalse(settings.isReversing)
        XCTAssertEqual(settings.axesToReverse(for: .mouse), [])
        XCTAssertEqual(settings.axesToReverse(for: .trackpad), [])
    }

    func testEachDeviceAndAxisIsItsOwnChoice() {
        let settings = ready {
            $0.reverseMouse = false
            $0.reverseTrackpad = true
            $0.reverseHorizontal = false
        }
        XCTAssertEqual(settings.axesToReverse(for: .mouse), [])
        XCTAssertEqual(settings.axesToReverse(for: .trackpad), .vertical)
    }

    func testWithNoDeviceOrNoAxisThereIsNothingToDo() {
        XCTAssertFalse(ready { $0.reverseMouse = false }.isReversing)
        XCTAssertFalse(ready { $0.reverseVertical = false; $0.reverseHorizontal = false }.isReversing)
        XCTAssertTrue(ready().isReversing)
    }

    func testAFileMissingKeysReadsWithDefaults() throws {
        let settings = try JSONDecoder().decode(ScrollSettings.self, from: Data(#"{"reverseTrackpad":true}"#.utf8))
        XCTAssertTrue(settings.reverseTrackpad)
        XCTAssertTrue(settings.reverseMouse)
        XCTAssertTrue(settings.isOn)
        XCTAssertFalse(settings.hasCompletedSetup)
    }

    func testRoundTrips() throws {
        let settings = ready { $0.reverseVertical = false }
        let decoded = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}

final class ScrollReversalTests: XCTestCase {
    func testVerticalIsAxisOne() {
        XCTAssertEqual(
            ScrollReversal.fields(for: .vertical).map(\.eventField),
            [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
        )
    }

    func testHorizontalIsAxisTwo() {
        XCTAssertEqual(
            ScrollReversal.fields(for: .horizontal).map(\.eventField),
            [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2]
        )
    }

    func testNoAxesNoFields() {
        XCTAssertEqual(ScrollReversal.fields(for: []), [])
    }

    /// Line deltas first: writing one makes macOS recompute the rest.
    func testLineDeltasAreWrittenBeforeTheOthers() {
        let fields = ScrollReversal.fields(for: .both)
        XCTAssertEqual(fields.count, 6)
        XCTAssertEqual(Set(fields.prefix(2)), [.lineVertical, .lineHorizontal])
        XCTAssertEqual(fields.filter(\.isFractional), [.fixedVertical, .fixedHorizontal])
    }

    func testReversingNegatesEveryDeltaOfTheAxis() {
        let event = FakeScrollEvent([
            .lineVertical: 1, .fixedVertical: 1, .pointVertical: 10,
            .lineHorizontal: 0, .fixedHorizontal: 0, .pointHorizontal: 0,
        ])
        ScrollReversal.reverse(.vertical, on: event)
        XCTAssertEqual(event.values[.lineVertical], -1)
        XCTAssertEqual(event.values[.fixedVertical], -1)
        XCTAssertEqual(event.values[.pointVertical], -10)
        XCTAssertEqual(event.writes, [.lineVertical, .fixedVertical, .pointVertical])
    }

    /// A smooth scroll's fractional distance survives the line-delta write,
    /// which on its own would have replaced it with a whole-line amount.
    func testSmoothDistancesSurviveTheRecompute() {
        let event = FakeScrollEvent([.lineVertical: 0, .fixedVertical: 0.37, .pointVertical: 3])
        ScrollReversal.reverse(.vertical, on: event)
        XCTAssertEqual(event.values[.fixedVertical] ?? 0, -0.37, accuracy: 1e-9)
        XCTAssertEqual(event.values[.pointVertical], -3)
    }

    func testOnlyTheChosenAxisChanges() {
        let event = FakeScrollEvent([.lineVertical: 2, .pointVertical: 16, .lineHorizontal: 1, .pointHorizontal: 8])
        ScrollReversal.reverse(.horizontal, on: event)
        XCTAssertEqual(event.values[.lineVertical], 2)
        XCTAssertEqual(event.values[.pointVertical], 16)
        XCTAssertEqual(event.values[.lineHorizontal], -1)
        XCTAssertEqual(event.values[.pointHorizontal], -8)
    }

    func testReversingNothingWritesNothing() {
        let event = FakeScrollEvent([.lineVertical: 1])
        ScrollReversal.reverse([], on: event)
        XCTAssertEqual(event.writes, [])
    }
}

final class ScrollLinkTests: XCTestCase {
    func testCommandsRoundTrip() {
        for command in [ScrollCommand.reload, .quit, .requestAccessibility] {
            XCTAssertEqual(ScrollCommand(encoded: command.encoded), command)
        }
        XCTAssertNil(ScrollCommand(encoded: "rm -rf"))
    }

    func testStatusRoundTrips() {
        var status = ScrollStatus()
        status.isTrusted = true
        status.isTapActive = true
        status.lastDevice = .mouse
        status.lastWasReversed = true
        XCTAssertEqual(status.encoded.flatMap(ScrollStatus.init(encoded:)), status)
    }

    func testTheCompanionFindsPerchsContainer() {
        let url = ScrollLink.configURL(home: URL(fileURLWithPath: "/Users/me"), hostBundleIdentifier: "org.ahlab.Perch")
        XCTAssertEqual(
            url.path,
            "/Users/me/Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/org.ahlab.perch.scroll/scroll.json"
        )
    }

    func testTheHostIsThreeLevelsUp() {
        let companion = URL(fileURLWithPath: "/Applications/Perch.app/Contents/Helpers/PerchScroll.app")
        XCTAssertEqual(ScrollLink.hostURL(ofCompanionAt: companion).path, "/Applications/Perch.app")
    }
}
