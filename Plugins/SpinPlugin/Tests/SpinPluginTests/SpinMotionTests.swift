@testable import SpinPlugin
import XCTest

final class SpinMotionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartsStill() {
        let motion = SpinMotion()
        XCTAssertEqual(motion.angle(at: t0.addingTimeInterval(10)), 0)
        XCTAssertEqual(motion.speed(at: t0), 0)
    }

    func testSpinsUpToFullSpeed() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        XCTAssertEqual(motion.speed(at: t0.addingTimeInterval(0.4)), 100, accuracy: 0.001)
        XCTAssertEqual(motion.speed(at: t0.addingTimeInterval(5)), 200, accuracy: 0.001)
        // Ramp covers 0.8 s at an average of 100°/s = 80°, then 200°/s after.
        XCTAssertEqual(motion.angle(at: t0.addingTimeInterval(1.8)), 80 + 200, accuracy: 0.001)
    }

    func testSpinsDownAndStops() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        let pause = t0.addingTimeInterval(10)
        let angleAtPause = motion.angle(at: pause)
        motion.setPlaying(false, at: pause)
        XCTAssertEqual(motion.speed(at: pause), 200, accuracy: 0.001)
        // Spin-down covers 1.5 s at an average of 100°/s = 150°.
        XCTAssertEqual(motion.angle(at: pause.addingTimeInterval(1.5)), angleAtPause + 150, accuracy: 0.001)
        XCTAssertEqual(motion.angle(at: pause.addingTimeInterval(60)), angleAtPause + 150, accuracy: 0.001)
    }

    func testAngleIsContinuousAcrossChanges() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        let mid = t0.addingTimeInterval(0.3)
        let before = motion.angle(at: mid)
        motion.setPlaying(false, at: mid)
        XCTAssertEqual(motion.angle(at: mid), before, accuracy: 0.001)
    }
}
