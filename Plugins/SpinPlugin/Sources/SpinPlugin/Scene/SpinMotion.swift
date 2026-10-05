import Foundation

/// The record's rotation as a function of time.
///
/// Speed ramps linearly between still and 33⅓ rpm, so play and pause ease
/// rather than snap. Angle is the integral of speed, anchored at the last
/// change, so it never jumps.
struct SpinMotion: Equatable, Sendable {
    static let degreesPerSecond = 200.0  // 33⅓ rpm
    static let spinUp: TimeInterval = 0.8
    static let spinDown: TimeInterval = 1.5

    private var anchorTime = Date.distantPast
    private var anchorAngle = 0.0
    private var fromSpeed = 0.0
    private var toSpeed = 0.0
    private var ramp: TimeInterval = 1

    func speed(at date: Date) -> Double {
        let progress = min(1, max(0, date.timeIntervalSince(anchorTime) / ramp))
        return fromSpeed + (toSpeed - fromSpeed) * progress
    }

    func angle(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(anchorTime))
        let ramping = min(elapsed, ramp)
        let during = fromSpeed * ramping + (toSpeed - fromSpeed) * ramping * ramping / (2 * ramp)
        let after = toSpeed * max(0, elapsed - ramp)
        return anchorAngle + during + after
    }

    mutating func setPlaying(_ playing: Bool, at date: Date) {
        let target = playing ? Self.degreesPerSecond : 0
        guard target != toSpeed else { return }
        anchorAngle = angle(at: date)
        fromSpeed = speed(at: date)
        toSpeed = target
        anchorTime = date
        ramp = playing ? Self.spinUp : Self.spinDown
    }
}
