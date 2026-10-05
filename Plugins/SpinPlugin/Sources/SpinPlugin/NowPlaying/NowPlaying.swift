import Foundation

/// The two players Spin understands. Anything else would need MediaRemote,
/// which macOS 15.4 restricted to entitled Apple processes.
public enum Player: String, CaseIterable, Sendable {
    case spotify
    case music

    public var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    /// Posted by the player on every play, pause, stop and track change.
    public var notificationName: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: Notification.Name("com.apple.Music.playerInfo")
        }
    }

    /// The name AppleScript knows the application by.
    var scriptName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }
}

public enum PlaybackState: String, Sendable {
    case playing
    case paused
    case stopped
}

public struct Track: Equatable, Sendable {
    /// Spotify's `spotify:track:…` URI, or Music's persistent ID in hex.
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let player: Player
}

/// One thing a player told us.
public struct PlayerEvent: Equatable, Sendable {
    public let player: Player
    public let state: PlaybackState
    /// `nil` when the player said nothing about a track — a stop, or an ad.
    public let track: Track?
}
