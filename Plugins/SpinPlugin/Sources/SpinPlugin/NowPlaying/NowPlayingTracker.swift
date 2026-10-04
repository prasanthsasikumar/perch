/// Decides which player's state is "now playing" when both report.
///
/// A player that starts playing takes over. A player that pauses or stops
/// only takes over if the current one is not playing either, so pausing a
/// forgotten Spotify does not hide the Music track you are listening to.
struct NowPlayingTracker {
    private var latest: [Player: PlayerEvent] = [:]
    private var active: Player?

    var current: PlayerEvent? { active.flatMap { latest[$0] } }

    /// Returns whether `current` changed.
    @discardableResult
    mutating func apply(_ incoming: PlayerEvent) -> Bool {
        let before = current
        var event = incoming
        // Spotify sometimes reports a pause without the track; keep the one we know.
        if event.track == nil, event.state != .stopped, let known = latest[event.player]?.track {
            event = PlayerEvent(player: event.player, state: event.state, track: known)
        }
        latest[event.player] = event

        if event.state == .playing || active == nil {
            active = event.player
        } else if let active, active != event.player, latest[active]?.state != .playing {
            self.active = event.player
        }
        return current != before
    }
}
