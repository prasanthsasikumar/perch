import Foundation

/// Whether the desktop scene is up, and whether its record turns.
enum SceneVisibility {
    enum Phase: Equatable, Sendable {
        case hidden
        /// On screen, record still: paused or stopped within the linger.
        case resting
        case spinning
    }

    /// How long the scene stays after the music stops.
    static let linger: TimeInterval = 120

    /// - Parameter lastPlayingAt: the last moment music was known to be
    ///   playing — set when playback ends, not only when it starts.
    static func phase(state: PlaybackState?, lastPlayingAt: Date?, now: Date) -> Phase {
        if state == .playing { return .spinning }
        guard let lastPlayingAt, now.timeIntervalSince(lastPlayingAt) < linger else { return .hidden }
        return .resting
    }
}
