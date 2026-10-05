@testable import SpinPlugin
import XCTest

final class PlayerNotificationTests: XCTestCase {
    private let spotify = Player.spotify.notificationName
    private let music = Player.music.notificationName

    func testSpotifyPlaying() {
        let event = PlayerNotification.parse(name: spotify, userInfo: [
            "Player State": "Playing", "Name": "Flashing Lights", "Artist": "Kanye West",
            "Album": "Graduation", "Track ID": "spotify:track:abc",
        ])
        XCTAssertEqual(event, PlayerEvent(
            player: .spotify, state: .playing,
            track: Track(id: "spotify:track:abc", title: "Flashing Lights", artist: "Kanye West",
                         album: "Graduation", player: .spotify)
        ))
    }

    func testSpotifyStoppedHasNoTrack() {
        let event = PlayerNotification.parse(name: spotify, userInfo: ["Player State": "Stopped"])
        XCTAssertEqual(event, PlayerEvent(player: .spotify, state: .stopped, track: nil))
    }

    func testMusicPausedUsesHexPersistentID() {
        let event = PlayerNotification.parse(name: music, userInfo: [
            "Player State": "Paused", "Name": "Time", "Artist": "Pink Floyd",
            "Album": "The Dark Side of the Moon", "PersistentID": NSNumber(value: Int64(-1)),
        ])
        XCTAssertEqual(event?.state, .paused)
        XCTAssertEqual(event?.track?.id, "FFFFFFFFFFFFFFFF")
    }

    func testPersistentIDIsZeroPadded() {
        XCTAssertEqual(PlayerNotification.musicPersistentID(255), "00000000000000FF")
    }

    func testUnknownStateOrNameIsIgnored() {
        XCTAssertNil(PlayerNotification.parse(name: spotify, userInfo: ["Player State": "Buffering"]))
        XCTAssertNil(PlayerNotification.parse(name: .init("com.example.other"), userInfo: ["Player State": "Playing"]))
        XCTAssertNil(PlayerNotification.parse(name: spotify, userInfo: nil))
    }

    func testMissingTitleGivesNoTrack() {
        let event = PlayerNotification.parse(name: spotify, userInfo: ["Player State": "Playing", "Track ID": "spotify:ad:1"])
        XCTAssertEqual(event, PlayerEvent(player: .spotify, state: .playing, track: nil))
    }
}
