@testable import TapKit
import XCTest

/// Synthetic sensor traces at the sensor's native 800 Hz: a quiet desk, and
/// knocks shaped like the ones MacTap's arrow-key simulation produces.
final class TapDetectorTests: XCTestCase {
    private let rate = 800.0
    private var gestures: [DetectedGesture] = []
    private var rejects: [String] = []
    private var time = 0.0
    private var secondsSinceKey = 100.0

    private func makeDetector(layout: GestureLayout = .knock) -> TapDetector {
        // The wall clock follows the trace, as it would live.
        let detector = TapDetector(clock: { [unowned self] in time }, secondsSinceLastKey: { [unowned self] in secondsSinceKey })
        var config = TapConfig.default
        config.layout = layout
        detector.apply(config)
        detector.onGesture = { [unowned self] in gestures.append($0) }
        detector.onReject = { [unowned self] in rejects.append($0) }
        return detector
    }

    private func quiet(_ detector: TapDetector, seconds: Double) {
        let count = Int(seconds * rate)
        for i in 0..<count {
            let jitter = i.isMultiple(of: 2) ? 0.001 : -0.001
            feed(detector, x: jitter, magnitude: 0.002)
        }
    }

    /// One knock: a sharp rise and a fast decay over ~15 ms.
    private func knock(_ detector: TapDetector, polarity: Double = 1) {
        for magnitude in [0.08, 0.20, 0.32, 0.26, 0.18, 0.12, 0.08, 0.05, 0.03, 0.01] {
            feed(detector, x: polarity * magnitude, magnitude: magnitude)
        }
    }

    private func feed(_ detector: TapDetector, x: Double, magnitude: Double) {
        detector.process(SensorSample(
            timestamp: time, x: x, y: 0, z: 0, magnitude: magnitude, rawMagnitude: 1 + magnitude
        ))
        time += 1 / rate
    }

    override func setUp() {
        gestures = []
        rejects = []
        time = 0
        secondsSinceKey = 100
    }

    func testOneKnockIsASingle() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        knock(detector)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.map(\.tapCount), [1])
    }

    func testTwoKnocksInTheWindowAreADouble() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        knock(detector)
        quiet(detector, seconds: 0.15)
        knock(detector)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.map(\.tapCount), [2])
    }

    func testThreeKnocksFireAtOnce() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        knock(detector)
        quiet(detector, seconds: 0.15)
        knock(detector)
        quiet(detector, seconds: 0.15)
        knock(detector)
        quiet(detector, seconds: 0.05)
        XCTAssertEqual(gestures.map(\.tapCount), [3])
    }

    func testKnocksFurtherApartThanTheWindowAreSeparate() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        knock(detector)
        quiet(detector, seconds: 0.8)
        knock(detector)
        quiet(detector, seconds: 0.8)
        XCTAssertEqual(gestures.map(\.tapCount), [1, 1])
    }

    func testAQuietDeskFiresNothing() {
        let detector = makeDetector()
        quiet(detector, seconds: 3)
        XCTAssertTrue(gestures.isEmpty)
    }

    func testKnocksWhileTypingAreIgnored() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        secondsSinceKey = 0.1
        knock(detector)
        quiet(detector, seconds: 0.6)
        XCTAssertTrue(gestures.isEmpty)
        XCTAssertTrue(rejects.contains("typing"))
    }

    func testTypingCanBeIgnoredOnPurpose() {
        let detector = makeDetector()
        detector.ignoreWhileTyping = false
        quiet(detector, seconds: 1)
        secondsSinceKey = 0.1
        knock(detector)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.count, 1)
    }

    func testAnywhereReportsTheLeftSide() {
        let detector = makeDetector()
        quiet(detector, seconds: 1)
        knock(detector, polarity: 1)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.first?.side, .left)
    }

    func testSidesFollowLateralDirection() {
        let detector = makeDetector(layout: .sides)
        quiet(detector, seconds: 1)
        knock(detector, polarity: 1)
        quiet(detector, seconds: 0.6)
        knock(detector, polarity: -1)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.map(\.side), [.right, .left])
    }

    func testInvertSwapsTheSides() {
        let detector = makeDetector(layout: .sides)
        detector.invertSides = true
        quiet(detector, seconds: 1)
        knock(detector, polarity: 1)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.first?.side, .left)
    }

    /// A knock on the other edge ends the first gesture without adding to it.
    func testSwitchingSidesSplitsTheGesture() {
        let detector = makeDetector(layout: .sides)
        quiet(detector, seconds: 1)
        knock(detector, polarity: 1)
        quiet(detector, seconds: 0.15)
        knock(detector, polarity: -1)
        quiet(detector, seconds: 0.6)
        XCTAssertEqual(gestures.map(\.side), [.right, .left])
        XCTAssertEqual(gestures.map(\.tapCount), [1, 1])
    }

    func testThresholdFollowsSensitivity() {
        XCTAssertEqual(TapDetector.threshold(sensitivity: 0), 0.050, accuracy: 1e-9)
        XCTAssertEqual(TapDetector.threshold(sensitivity: 1), 0.012, accuracy: 1e-9)
        XCTAssertLessThan(TapDetector.threshold(sensitivity: 0.7), TapDetector.threshold(sensitivity: 0.3))
    }
}
