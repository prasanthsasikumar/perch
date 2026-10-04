@testable import SpinPlugin
import XCTest

final class SceneVisibilityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPlayingSpins() {
        XCTAssertEqual(SceneVisibility.phase(state: .playing, lastPlayingAt: nil, now: t0), .spinning)
    }

    func testNothingEverPlayedIsHidden() {
        XCTAssertEqual(SceneVisibility.phase(state: nil, lastPlayingAt: nil, now: t0), .hidden)
        XCTAssertEqual(SceneVisibility.phase(state: .paused, lastPlayingAt: nil, now: t0), .hidden)
    }

    func testPausedRestsWithinLinger() {
        let phase = SceneVisibility.phase(state: .paused, lastPlayingAt: t0, now: t0.addingTimeInterval(119))
        XCTAssertEqual(phase, .resting)
    }

    func testStoppedHidesAfterLinger() {
        let phase = SceneVisibility.phase(state: .stopped, lastPlayingAt: t0, now: t0.addingTimeInterval(120))
        XCTAssertEqual(phase, .hidden)
    }

    /// Review Focus 1: `lastPlayingAt` is when playback ended, so an hour of
    /// listening followed by a pause still rests for the full linger.
    func testPauseAfterLongPlaybackStillLingers() {
        let pausedAt = t0.addingTimeInterval(3600)
        let phase = SceneVisibility.phase(state: .paused, lastPlayingAt: pausedAt, now: pausedAt.addingTimeInterval(5))
        XCTAssertEqual(phase, .resting)
    }
}
