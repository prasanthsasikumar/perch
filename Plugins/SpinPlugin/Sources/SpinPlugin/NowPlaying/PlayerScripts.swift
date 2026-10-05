import Foundation

enum PlayerScripts {
    /// Returns `state` alone when stopped, otherwise state, title, artist,
    /// album and id on separate lines.
    static func state(of player: Player) -> String {
        let idProperty = player == .spotify ? "id" : "persistent ID"
        return whileRunning(player, """
        tell application "\(player.scriptName)"
            set s to player state as string
            if s is "stopped" then return s
            set t to current track
            return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (\(idProperty) of t)
        end tell
        """)
    }

    /// Asks for the art only if the player is still on `track`, so a skip
    /// between the notification and the script cannot file one track's art
    /// under another's id.
    static func artwork(of track: Track) -> String {
        let id = track.id.filter { $0 != "\"" && $0 != "\\" }
        switch track.player {
        case .spotify:
            return whileRunning(.spotify, """
            tell application "Spotify"
                if id of current track is "\(id)" then return artwork url of current track
            end tell
            """)
        case .music:
            return whileRunning(.music, """
            tell application "Music"
                if persistent ID of current track is "\(id)" then return data of artwork 1 of current track
            end tell
            """)
        }
    }

    /// `PlayerProcess.isRunning` is checked before a script is queued, but a
    /// script can wait in the queue behind a slow one or a permission prompt.
    /// Checking again inside the script, where it cannot launch the app,
    /// keeps a player the user just quit from being reopened.
    private static func whileRunning(_ player: Player, _ body: String) -> String {
        "if application \"\(player.scriptName)\" is running then\n\(body)\nend if"
    }

    static func parseState(_ text: String, player: Player) -> PlayerEvent? {
        let lines = text.components(separatedBy: "\n")
        guard let state = lines.first.flatMap({ PlaybackState(rawValue: $0) }) else { return nil }
        guard state != .stopped, lines.count >= 5, !lines[1].isEmpty else {
            return PlayerEvent(player: player, state: state, track: nil)
        }
        return PlayerEvent(
            player: player,
            state: state,
            track: Track(id: lines[4], title: lines[1], artist: lines[2], album: lines[3], player: player)
        )
    }
}

protocol PlayerQuerying: Sendable {
    func event(for player: Player) async -> PlayerEvent?
}

/// Reads a running player's state directly: once at start, and whenever a
/// notification arrives without a usable payload.
struct ScriptedPlayerQuery: PlayerQuerying {
    let runner: AppleScriptRunning
    var isRunning: @Sendable (Player) -> Bool = { PlayerProcess.isRunning($0) }

    func event(for player: Player) async -> PlayerEvent? {
        guard isRunning(player),
              case .text(let text)? = try? await runner.run(PlayerScripts.state(of: player))
        else { return nil }
        return PlayerScripts.parseState(text, player: player)
    }
}
