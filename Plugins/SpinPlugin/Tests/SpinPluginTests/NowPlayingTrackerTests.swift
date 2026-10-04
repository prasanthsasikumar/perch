@testable import SpinPlugin
import XCTest

final class NowPlayingTrackerTests: XCTestCase {
    private func track(_ id: String, _ player: Player) -> Track {
        Track(id: id, title: id, artist: "A", album: "B", player: player)
    }

    private func event(_ player: Player, _ state: PlaybackState, _ id: String? = nil) -> PlayerEvent {
        PlayerEvent(player: player, state: state, track: id.map { track($0, player) })
    }

    func testFirstEventBecomesCurrent() {
        var tracker = NowPlayingTracker()
        XCTAssertTrue(tracker.apply(event(.spotify, .playing, "a")))
        XCTAssertEqual(tracker.current, event(.spotify, .playing, "a"))
    }

    func testLatestStartedPlayerWins() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .playing, "a"))
        tracker.apply(event(.music, .playing, "m"))
        XCTAssertEqual(tracker.current?.player, .music)
    }

    func testOtherPlayerPausingDoesNotStealFocus() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .playing, "a"))
        tracker.apply(event(.music, .playing, "m"))
        XCTAssertFalse(tracker.apply(event(.spotify, .paused, "a")))
        XCTAssertEqual(tracker.current, event(.music, .playing, "m"))
    }

    func testWhenNothingPlaysTheMostRecentUpdateWins() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .paused, "a"))
        tracker.apply(event(.music, .paused, "m"))
        XCTAssertEqual(tracker.current?.player, .music)
    }

    func testTracklessPauseKeepsTheKnownTrack() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .playing, "a"))
        tracker.apply(PlayerEvent(player: .spotify, state: .paused, track: nil))
        XCTAssertEqual(tracker.current, event(.spotify, .paused, "a"))
    }

    func testStopForgetsTheTrack() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .playing, "a"))
        tracker.apply(event(.spotify, .stopped))
        XCTAssertEqual(tracker.current, event(.spotify, .stopped))
    }

    func testRepeatedIdenticalEventReportsNoChange() {
        var tracker = NowPlayingTracker()
        tracker.apply(event(.spotify, .playing, "a"))
        XCTAssertFalse(tracker.apply(event(.spotify, .playing, "a")))
    }
}
