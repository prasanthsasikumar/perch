@testable import SpinPlugin
import XCTest

final class PlayerScriptsTests: XCTestCase {
    func testParsesPlayingState() {
        let text = "playing\nFlashing Lights\nKanye West\nGraduation\nspotify:track:abc"
        XCTAssertEqual(PlayerScripts.parseState(text, player: .spotify), PlayerEvent(
            player: .spotify, state: .playing,
            track: Track(id: "spotify:track:abc", title: "Flashing Lights", artist: "Kanye West",
                         album: "Graduation", player: .spotify)
        ))
    }

    func testParsesStoppedWithoutTrack() {
        XCTAssertEqual(PlayerScripts.parseState("stopped", player: .music),
                       PlayerEvent(player: .music, state: .stopped, track: nil))
    }

    func testUnknownStateIsNil() {
        XCTAssertNil(PlayerScripts.parseState("fast forwarding\nx\ny\nz\nid", player: .music))
    }

    func testArtworkScriptChecksTheTrackAndStripsQuotes() {
        let script = PlayerScripts.artwork(of: makeTrack("spotify:track:a\"b"))
        XCTAssertTrue(script.contains("id of current track is \"spotify:track:ab\""))
        XCTAssertTrue(script.contains("artwork url"))
        XCTAssertTrue(PlayerScripts.artwork(of: makeTrack("00FF", .music)).contains("persistent ID"))
    }

    /// Final review 3: a script queued behind a slow one must not relaunch a
    /// player the user quit meanwhile, so each script checks for itself.
    func testScriptsDoNothingWhenThePlayerIsNotRunning() {
        for player in Player.allCases {
            XCTAssertTrue(PlayerScripts.state(of: player).hasPrefix("if application \"\(player.scriptName)\" is running then"))
            XCTAssertTrue(PlayerScripts.artwork(of: makeTrack("x", player)).hasPrefix("if application \"\(player.scriptName)\" is running then"))
        }
    }
}
