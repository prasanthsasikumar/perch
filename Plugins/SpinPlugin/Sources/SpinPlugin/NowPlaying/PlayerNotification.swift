import Foundation

/// Turns a player's distributed notification into a `PlayerEvent`.
///
/// Pure, so it can be tested against payloads captured from the real apps.
enum PlayerNotification {
    static func parse(name: Notification.Name, userInfo: [AnyHashable: Any]?) -> PlayerEvent? {
        guard let player = Player.allCases.first(where: { $0.notificationName == name }),
              let info = userInfo,
              let raw = info["Player State"] as? String,
              let state = PlaybackState(rawValue: raw.lowercased())
        else { return nil }
        return PlayerEvent(player: player, state: state, track: track(of: player, in: info))
    }

    private static func track(of player: Player, in info: [AnyHashable: Any]) -> Track? {
        guard let title = info["Name"] as? String, !title.isEmpty,
              let id = trackID(of: player, in: info)
        else { return nil }
        return Track(
            id: id,
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            player: player
        )
    }

    private static func trackID(of player: Player, in info: [AnyHashable: Any]) -> String? {
        switch player {
        case .spotify:
            guard let id = info["Track ID"] as? String, !id.isEmpty else { return nil }
            return id
        case .music:
            guard let number = info["PersistentID"] as? NSNumber else { return nil }
            return musicPersistentID(number.int64Value)
        }
    }

    /// Music's notification carries the persistent ID as a signed 64-bit
    /// number; AppleScript reports it as 16 uppercase hex digits. Using the
    /// AppleScript form everywhere keeps one track one cache entry.
    static func musicPersistentID(_ value: Int64) -> String {
        let hex = String(UInt64(bitPattern: value), radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}
