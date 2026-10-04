# Spin Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Perch plugin that, while Spotify or Apple Music plays, shows a room-with-a-turntable scene on the desktop with the album art as the spinning record's label and as a sleeve.

**Architecture:** A new SPM package `Plugins/SpinPlugin`. Pure logic (notification parsing, player arbitration, visibility timing, spin motion, scene geometry) is unit-tested; a `SpinModel` composes them behind injected seams (artwork provider, player query, clock); a `DesktopSceneController` owns a borderless click-through window at desktop level hosting a SwiftUI `SceneView`. Track state comes from the players' distributed notifications; artwork and the one-shot state read come from Apple Events (`NSAppleScript`).

**Tech Stack:** Swift 5.9 tools, SwiftUI + AppKit, XCTest, macOS 14+, xcodegen, Python 3 stdlib (scene generation via the Gemini REST API) and Pillow (overlay check).

**Spec:** `docs/superpowers/specs/2026-10-04-spin-plugin-design.md`

## Global Constraints

- Identifier `org.ahlab.perch.spin`, display name `Spin`, icon `record.circle`. Never `Vinyl` as a name.
- macOS 14 minimum; `swift-tools-version: 5.9`; the plugin depends only on `PerchKit`.
- Capabilities: `[.network, .media]`; `.media` disclosure is exactly `"Reads what's playing in Spotify and Music"`.
- Apple Events go only to `com.spotify.client` and `com.apple.Music`, only when that app is already running, and only while "Show scene on desktop" is on.
- **Deviation from spec, decided while planning:** "Show scene on desktop" defaults to **off**. New plugins arrive enabled for upgraders; defaulting on would raise an Automation prompt and cover their desktop unannounced (same reason Tap waits for setup). The panel invites the user to turn it on.
- **Deviation:** `tonearm` is optional in `scene.json` (a generated photo may already contain one), and the sleeve is a square `{x, y, size, rotation, style}` (album art is square).
- Linger after playback ends: 120 s. Spin speed 33⅓ rpm = 200°/s. Spin-up 0.8 s, spin-down 1.5 s.
- "Main display" means `NSScreen.screens.first` (the menu-bar display), not `NSScreen.main` (which follows key focus).
- After adding or moving any file under `Perch/` or changing `project.yml`, run `xcodegen generate` before `xcodebuild`.
- Plugin tests: `swift test --package-path Plugins/SpinPlugin`. Host tests: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS'`.

## Review Focus

1. **Pausing after a long listen** — the 2-minute linger counts from when playback *ended*, not when it started; the scene must not vanish instantly. (Task 3 test `testPauseAfterLongPlaybackStillLingers`.)
2. **Skipping tracks quickly** — a slow artwork fetch for an earlier track must never replace a newer track's art. (Task 6 test `testStaleArtworkIsDiscarded`.)
3. **Automation permission denied** — no crash, a fallback label, and the panel explains how to grant it. (Task 5 test `testDeniedPermissionIsReported`; Task 6 test `testNotPermittedStatus`.)
4. **Player not running / ad with no artwork** — never send an Apple Event that would launch a quit app; an empty artwork URL is "no art", not an error. (Task 5 tests `testQuitPlayerIsNeverScripted`, `testEmptyArtworkURLIsNone`.)
5. **Plugin disabled or toggle turned off mid-playback** — window closed, observers removed, no further scripts. (Task 6 test `testResetClearsEverything`, `testTogglingSceneOffHidesWindow`; Task 9 manual check.)

---

### Task 1: Package scaffold, `.media` capability, player notification parsing

**Files:**
- Create: `Plugins/SpinPlugin/Package.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/NowPlaying.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/PlayerNotification.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/PlayerNotificationTests.swift`
- Modify: `PerchKit/Sources/PerchKit/PluginCapability.swift`
- Modify: `PerchTests/PerchKit/PluginCapabilityTests.swift`

**Interfaces:**
- Produces: `public enum Player: String, CaseIterable { spotify, music }` with `bundleIdentifier`, `displayName`, `notificationName`, `scriptName`; `public enum PlaybackState: String { playing, paused, stopped }`; `public struct Track: Equatable, Sendable { id, title, artist, album, player }`; `public struct PlayerEvent: Equatable, Sendable { player, state, track: Track? }`; `enum PlayerNotification { static func parse(name: Notification.Name, userInfo: [AnyHashable: Any]?) -> PlayerEvent?; static func musicPersistentID(_ value: Int64) -> String }`; `PluginCapability.media`.

- [ ] **Step 1: Capture real notification payloads**

Write `scratchpad/listen.swift` (outside the repo):

```swift
import Foundation
for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
    DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { note in
        print(note.name.rawValue)
        for (key, value) in note.userInfo ?? [:] { print("  \(key) = \(value) [\(type(of: value))]") }
    }
}
RunLoop.main.run(until: Date().addingTimeInterval(20))
```

Run `swift scratchpad/listen.swift &`, then `osascript -e 'tell application "Spotify" to play'`, wait 3 s, `osascript -e 'tell application "Spotify" to pause'`. Repeat with `"Music"` if the library has tracks. Expected: keys `Player State`, `Name`, `Artist`, `Album`, `Track ID` (Spotify, a `spotify:track:…` string) and `PersistentID` (Music, an NSNumber). If any key differs, use the observed key in Step 3 and the tests.

- [ ] **Step 2: Write the package manifest and the failing tests**

`Plugins/SpinPlugin/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpinPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpinPlugin", targets: ["SpinPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(
            name: "SpinPlugin",
            dependencies: ["PerchKit"],
            resources: [.copy("Scene/Resources/scenes")]
        ),
        .testTarget(name: "SpinPluginTests", dependencies: ["SpinPlugin", "PerchKit"]),
    ]
)
```

Create `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/.gitkeep` so the resource path exists until Task 7.

`PlayerNotificationTests.swift`:

```swift
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
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | tail -5`
Expected: build failure, `cannot find 'PlayerNotification' in scope`.

- [ ] **Step 4: Implement**

`NowPlaying.swift`:

```swift
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
```

`PlayerNotification.swift`:

```swift
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
```

In `PluginCapability.swift`, add `case media` after `accessibility`, and in `disclosure`:

```swift
        case .media: "Reads what's playing in Spotify and Music"
```

In `PluginCapabilityTests.testEachCapabilityHasADisclosure` (the method containing the `.accessibility` assertion), append:

```swift
        XCTAssertEqual(
            Set([PluginCapability.media]).disclosureLines,
            ["Reads what's playing in Spotify and Music"]
        )
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "Executed|error"`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Plugins/SpinPlugin PerchKit/Sources/PerchKit/PluginCapability.swift PerchTests/PerchKit/PluginCapabilityTests.swift
git commit -m "feat(spin): package, media capability, player notification parsing"
```

---

### Task 2: `NowPlayingTracker` — which player is "now playing"

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/NowPlayingTracker.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/NowPlayingTrackerTests.swift`

**Interfaces:**
- Consumes: `Player`, `PlayerEvent`, `Track` (Task 1).
- Produces: `struct NowPlayingTracker { var current: PlayerEvent? { get }; @discardableResult mutating func apply(_ event: PlayerEvent) -> Bool }` — returns whether `current` changed.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin --filter NowPlayingTrackerTests 2>&1 | tail -3`
Expected: build failure, `cannot find 'NowPlayingTracker'`.

- [ ] **Step 3: Implement**

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin --filter NowPlayingTrackerTests 2>&1 | grep Executed`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Plugins/SpinPlugin
git commit -m "feat(spin): arbitrate between Spotify and Music"
```

---

### Task 3: `SceneVisibility` and `SpinMotion` — when to show, how the record turns

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/SceneVisibility.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/SpinMotion.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SceneVisibilityTests.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SpinMotionTests.swift`

**Interfaces:**
- Consumes: `PlaybackState`.
- Produces: `enum SceneVisibility { enum Phase { hidden, resting, spinning }; static let linger: TimeInterval; static func phase(state: PlaybackState?, lastPlayingAt: Date?, now: Date) -> Phase }`. `struct SpinMotion { static let degreesPerSecond = 200.0; static let spinUp = 0.8; static let spinDown = 1.5; func angle(at: Date) -> Double; func speed(at: Date) -> Double; mutating func setPlaying(_ playing: Bool, at: Date) }`.
- Contract for callers: `lastPlayingAt` is "the last moment we knew music was playing" — callers set it on every event where the state is or *was* `.playing` (Task 6 does this).

- [ ] **Step 1: Write the failing tests**

`SceneVisibilityTests.swift`:

```swift
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
```

`SpinMotionTests.swift`:

```swift
@testable import SpinPlugin
import XCTest

final class SpinMotionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartsStill() {
        let motion = SpinMotion()
        XCTAssertEqual(motion.angle(at: t0.addingTimeInterval(10)), 0)
        XCTAssertEqual(motion.speed(at: t0), 0)
    }

    func testSpinsUpToFullSpeed() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        XCTAssertEqual(motion.speed(at: t0.addingTimeInterval(0.4)), 100, accuracy: 0.001)
        XCTAssertEqual(motion.speed(at: t0.addingTimeInterval(5)), 200, accuracy: 0.001)
        // Ramp covers 0.8 s at an average of 100°/s = 80°, then 200°/s after.
        XCTAssertEqual(motion.angle(at: t0.addingTimeInterval(1.8)), 80 + 200, accuracy: 0.001)
    }

    func testSpinsDownAndStops() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        let pause = t0.addingTimeInterval(10)
        let angleAtPause = motion.angle(at: pause)
        motion.setPlaying(false, at: pause)
        XCTAssertEqual(motion.speed(at: pause), 200, accuracy: 0.001)
        // Spin-down covers 1.5 s at an average of 100°/s = 150°.
        XCTAssertEqual(motion.angle(at: pause.addingTimeInterval(1.5)), angleAtPause + 150, accuracy: 0.001)
        XCTAssertEqual(motion.angle(at: pause.addingTimeInterval(60)), angleAtPause + 150, accuracy: 0.001)
    }

    func testAngleIsContinuousAcrossChanges() {
        var motion = SpinMotion()
        motion.setPlaying(true, at: t0)
        let mid = t0.addingTimeInterval(0.3)
        let before = motion.angle(at: mid)
        motion.setPlaying(false, at: mid)
        XCTAssertEqual(motion.angle(at: mid), before, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SceneVisibility'` / `'SpinMotion'`.

- [ ] **Step 3: Implement**

`SceneVisibility.swift`:

```swift
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
```

`SpinMotion.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep Executed`
Expected: all tests pass (22 so far).

- [ ] **Step 5: Commit**

```bash
git add Plugins/SpinPlugin
git commit -m "feat(spin): scene visibility timing and record spin motion"
```

---

### Task 4: `SceneDescriptor`, `SceneLayout`, `SceneCatalog`

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/SceneDescriptor.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/SceneLayout.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/SceneCatalog.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SceneLayoutTests.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SceneCatalogTests.swift`

**Interfaces:**
- Produces: `SceneDescriptor` (Codable; fields below), `SceneFrames`, `TonearmFrame`, `enum SceneLayout { static func frames(for: SceneDescriptor, imageSize: CGSize, in screen: CGSize) -> SceneFrames }`, `struct SceneAsset: Identifiable { descriptor; backgroundURL; thumbnailURL; id }`, `enum SceneCatalog { static func load(from root: URL) -> [SceneAsset]; static var builtIn: [SceneAsset] }`.
- Geometry conventions (also used by `scripts/scene_overlay.py` in Task 7): all fractions are of the background image, origin top-left, y down. `x, y` are centres. `radius`, `size` and tonearm `length` are fractions of image **width**. Tonearm angles are degrees; 0 points straight down from the pivot; positive swings the tip toward −x (clockwise on screen, SwiftUI's `rotationEffect` convention).

- [ ] **Step 1: Write the failing tests**

`SceneLayoutTests.swift`:

```swift
@testable import SpinPlugin
import XCTest

final class SceneLayoutTests: XCTestCase {
    private func descriptor(platterX: Double, platterY: Double) -> SceneDescriptor {
        SceneDescriptor(
            id: "t", name: "T", order: 0,
            platter: .init(x: platterX, y: platterY, radius: 0.1, squash: 0.4),
            tonearm: .init(pivotX: 0.6, pivotY: 0.4, length: 0.1, restAngle: 5, playAngle: 25),
            sleeve: .init(x: 0.2, y: 0.5, size: 0.2, rotation: -3, style: .stand)
        )
    }

    private let image = CGSize(width: 3000, height: 2000)  // 3:2

    func testSixteenByTenCropsTopAndBottom() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.5), imageSize: image,
                                        in: CGSize(width: 1440, height: 900))
        // scale = max(1440/3000, 900/2000) = 0.48 → 1440×960, 30 pt cropped top and bottom.
        XCTAssertEqual(frames.imageRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.minY, -30, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.width, 1440, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.height, 960, accuracy: 0.001)
        XCTAssertEqual(frames.platterCenter.x, 720, accuracy: 0.001)
        XCTAssertEqual(frames.platterCenter.y, 450, accuracy: 0.001)
        XCTAssertEqual(frames.platterRadius, 144, accuracy: 0.001)
        XCTAssertEqual(frames.squash, 0.4)
    }

    func testSixteenByNine() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.25), imageSize: image,
                                        in: CGSize(width: 1920, height: 1080))
        // scale 0.64 → 1920×1280, offset y −100.
        XCTAssertEqual(frames.platterCenter.y, -100 + 0.25 * 1280, accuracy: 0.001)
    }

    func testUltrawideCropsHeavily() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.25, platterY: 0.75), imageSize: image,
                                        in: CGSize(width: 3440, height: 1440))
        // scale 3440/3000 → 3440×2293.33, offset y −426.67.
        XCTAssertEqual(frames.platterCenter.x, 860, accuracy: 0.01)
        XCTAssertEqual(frames.platterCenter.y, 1293.33, accuracy: 0.01)
    }

    func testTonearmAndSleeveScale() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.5), imageSize: image,
                                        in: CGSize(width: 1440, height: 900))
        XCTAssertEqual(frames.tonearm?.pivot.x ?? 0, 0.6 * 1440, accuracy: 0.001)
        XCTAssertEqual(frames.tonearm?.length ?? 0, 144, accuracy: 0.001)
        XCTAssertEqual(frames.sleeveSize, 288, accuracy: 0.001)
        XCTAssertEqual(frames.sleeveCenter.y, -30 + 0.5 * 960, accuracy: 0.001)
    }
}
```

`SceneCatalogTests.swift`:

```swift
@testable import SpinPlugin
import XCTest

final class SceneCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ id: String, order: Int, background: Bool = true, json: String? = nil) throws {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = json ?? """
        {"id":"\(id)","name":"\(id)","order":\(order),
         "platter":{"x":0.5,"y":0.5,"radius":0.1,"squash":0.4},
         "sleeve":{"x":0.2,"y":0.5,"size":0.2,"rotation":0,"style":"flat"}}
        """
        try body.write(to: dir.appendingPathComponent("scene.json"), atomically: true, encoding: .utf8)
        if background { try Data([0]).write(to: dir.appendingPathComponent("background.jpg")) }
    }

    func testLoadsScenesInOrder() throws {
        try write("b", order: 2)
        try write("a", order: 1)
        XCTAssertEqual(SceneCatalog.load(from: root).map(\.id), ["a", "b"])
    }

    func testSkipsSceneWithoutBackground() throws {
        try write("a", order: 1, background: false)
        XCTAssertTrue(SceneCatalog.load(from: root).isEmpty)
    }

    func testSkipsUnreadableJSON() throws {
        try write("a", order: 1, json: "{")
        XCTAssertTrue(SceneCatalog.load(from: root).isEmpty)
    }

    func testTonearmIsOptional() throws {
        try write("a", order: 1)
        XCTAssertNil(SceneCatalog.load(from: root).first?.descriptor.tonearm)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SceneDescriptor'`.

- [ ] **Step 3: Implement**

`SceneDescriptor.swift`:

```swift
import Foundation

/// Where a scene's drawn parts sit on its background photo.
///
/// Every number is a fraction of the photo (origin top-left, y down) so one
/// file serves every screen. Lengths are fractions of the photo's width.
struct SceneDescriptor: Codable, Equatable, Identifiable, Sendable {
    struct Platter: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var radius: Double
        /// Vertical scale of the record ellipse: the photo looks down at an angle.
        var squash: Double
    }

    /// Angles in degrees: 0 points straight down from the pivot, positive
    /// swings the tip toward the left.
    struct Tonearm: Codable, Equatable, Sendable {
        var pivotX: Double
        var pivotY: Double
        var length: Double
        var restAngle: Double
        var playAngle: Double
    }

    struct Sleeve: Codable, Equatable, Sendable {
        enum Style: String, Codable, Sendable {
            /// Upright in a stand, facing the viewer.
            case stand
            /// Lying on the desk, tipped away in perspective.
            case flat
        }

        var x: Double
        var y: Double
        var size: Double
        var rotation: Double
        var style: Style
    }

    var id: String
    var name: String
    var order: Int
    var platter: Platter
    /// `nil` when the photo already shows its own arm.
    var tonearm: Tonearm?
    var sleeve: Sleeve
}
```

`SceneLayout.swift`:

```swift
import CoreGraphics

struct TonearmFrame: Equatable {
    var pivot: CGPoint
    var length: CGFloat
    var restAngle: Double
    var playAngle: Double
}

/// A scene placed on a particular screen, in screen points.
struct SceneFrames: Equatable {
    var imageRect: CGRect
    var platterCenter: CGPoint
    var platterRadius: CGFloat
    var squash: CGFloat
    var tonearm: TonearmFrame?
    var sleeveCenter: CGPoint
    var sleeveSize: CGFloat
    var sleeveRotation: Double
}

/// Aspect-fills the background onto the screen (cropping, never letterboxing)
/// and carries every drawn part along with it.
enum SceneLayout {
    static func frames(for scene: SceneDescriptor, imageSize: CGSize, in screen: CGSize) -> SceneFrames {
        let scale = max(screen.width / imageSize.width, screen.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let imageRect = CGRect(
            x: (screen.width - drawn.width) / 2,
            y: (screen.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: imageRect.minX + x * drawn.width, y: imageRect.minY + y * drawn.height)
        }
        func length(_ fraction: Double) -> CGFloat { fraction * drawn.width }

        return SceneFrames(
            imageRect: imageRect,
            platterCenter: point(scene.platter.x, scene.platter.y),
            platterRadius: length(scene.platter.radius),
            squash: scene.platter.squash,
            tonearm: scene.tonearm.map {
                TonearmFrame(pivot: point($0.pivotX, $0.pivotY), length: length($0.length),
                             restAngle: $0.restAngle, playAngle: $0.playAngle)
            },
            sleeveCenter: point(scene.sleeve.x, scene.sleeve.y),
            sleeveSize: length(scene.sleeve.size),
            sleeveRotation: scene.sleeve.rotation
        )
    }
}
```

`SceneCatalog.swift`:

```swift
import Foundation

/// A scene on disk: `<root>/<id>/{scene.json, background.jpg, thumb.jpg}`.
struct SceneAsset: Identifiable, Equatable, Sendable {
    var descriptor: SceneDescriptor
    var backgroundURL: URL
    var thumbnailURL: URL
    var id: String { descriptor.id }
}

enum SceneCatalog {
    /// The scenes shipped in the bundle.
    static var builtIn: [SceneAsset] {
        guard let root = Bundle.module.url(forResource: "scenes", withExtension: nil) else { return [] }
        return load(from: root)
    }

    /// A folder that is missing its photo or whose JSON does not decode is
    /// skipped rather than failing the whole catalogue.
    static func load(from root: URL) -> [SceneAsset] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return folders.compactMap { folder in
            let background = folder.appendingPathComponent("background.jpg")
            guard FileManager.default.fileExists(atPath: background.path),
                  let data = try? Data(contentsOf: folder.appendingPathComponent("scene.json")),
                  let descriptor = try? JSONDecoder().decode(SceneDescriptor.self, from: data)
            else { return nil }
            return SceneAsset(
                descriptor: descriptor,
                backgroundURL: background,
                thumbnailURL: folder.appendingPathComponent("thumb.jpg")
            )
        }
        .sorted { $0.descriptor.order < $1.descriptor.order }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep Executed`
Expected: 0 failures (30 tests).

- [ ] **Step 5: Commit**

```bash
git add Plugins/SpinPlugin
git commit -m "feat(spin): scene descriptors, layout and catalogue"
```

---

### Task 5: Apple Events — script runner, player query, artwork fetcher

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/AppleScriptRunner.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/PlayerScripts.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/ArtworkFetcher.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SpinTestSupport.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/PlayerScriptsTests.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/ArtworkFetcherTests.swift`

**Interfaces:**
- Consumes: `Player`, `Track`, `PlayerEvent`, `PlaybackState`, `PlayerNotification` (Task 1).
- Produces:
  - `enum ScriptValue: Equatable, Sendable { case text(String), data(Data), none }`, `enum ScriptError: Error, Equatable { case notPermitted, failed(Int) }`, `protocol AppleScriptRunning: Sendable { func run(_ source: String) async throws -> ScriptValue }`, `final class NSAppleScriptRunner: AppleScriptRunning`.
  - `enum PlayerProcess { static func isRunning(_ player: Player) -> Bool }`.
  - `enum PlayerScripts { static func state(of: Player) -> String; static func artwork(of: Track) -> String; static func parseState(_ text: String, player: Player) -> PlayerEvent? }`.
  - `protocol PlayerQuerying: Sendable { func event(for player: Player) async -> PlayerEvent? }`, `struct ScriptedPlayerQuery: PlayerQuerying`.
  - `enum ArtworkResult: Equatable, Sendable { case image(Data), none, notPermitted }`, `protocol ArtworkProviding: Sendable { func artwork(for track: Track) async -> ArtworkResult }`, `actor ArtworkFetcher: ArtworkProviding { init(runner:cacheDirectory:isRunning:download:) }`.

- [ ] **Step 1: Write the test fakes and failing tests**

`SpinTestSupport.swift`:

```swift
@testable import SpinPlugin
import AppKit
import Foundation

/// Answers each script with a queued value and records what it was asked.
final class FakeScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _sources: [String] = []
    var result: Result<ScriptValue, ScriptError> = .success(.none)

    var sources: [String] { lock.withLock { _sources } }

    func run(_ source: String) async throws -> ScriptValue {
        lock.withLock { _sources.append(source) }
        return try result.get()
    }
}

/// Valid PNG bytes of a given pixel size, so tests can tell images apart.
func pngData(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

func makeTrack(_ id: String, _ player: Player = .spotify) -> Track {
    Track(id: id, title: "Title \(id)", artist: "Artist", album: "Album", player: player)
}
```

`PlayerScriptsTests.swift`:

```swift
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
}
```

`ArtworkFetcherTests.swift`:

```swift
@testable import SpinPlugin
import XCTest

final class ArtworkFetcherTests: XCTestCase {
    private var cache: URL!
    private let runner = FakeScriptRunner()

    override func setUp() {
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache)
    }

    private func fetcher(running: Bool = true, download: @escaping @Sendable (URL) async throws -> Data = { _ in pngData(size: 4) }) -> ArtworkFetcher {
        ArtworkFetcher(runner: runner, cacheDirectory: cache, isRunning: { _ in running }, download: download)
    }

    func testSpotifyURLIsDownloadedAndCached() async {
        runner.result = .success(.text("https://i.scdn.co/image/x"))
        let fetcher = fetcher()
        let first = await fetcher.artwork(for: makeTrack("a"))
        XCTAssertEqual(first, .image(pngData(size: 4)))
        runner.result = .failure(.failed(-1))
        let second = await fetcher.artwork(for: makeTrack("a"))
        XCTAssertEqual(second, .image(pngData(size: 4)), "second call is served from the cache")
        XCTAssertEqual(runner.sources.count, 1)
    }

    func testMusicDataIsUsedDirectly() async {
        runner.result = .success(.data(pngData(size: 2)))
        let result = await fetcher().artwork(for: makeTrack("00FF", .music))
        XCTAssertEqual(result, .image(pngData(size: 2)))
    }

    /// Review Focus 4.
    func testQuitPlayerIsNeverScripted() async {
        let result = await fetcher(running: false).artwork(for: makeTrack("a"))
        XCTAssertEqual(result, .none)
        XCTAssertTrue(runner.sources.isEmpty)
    }

    /// Review Focus 4: ads report an empty artwork URL.
    func testEmptyArtworkURLIsNone() async {
        runner.result = .success(.text(""))
        let result = await fetcher().artwork(for: makeTrack("spotify:ad:1"))
        XCTAssertEqual(result, .none)
    }

    /// Review Focus 3.
    func testDeniedPermissionIsReported() async {
        runner.result = .failure(.notPermitted)
        let result = await fetcher().artwork(for: makeTrack("a"))
        XCTAssertEqual(result, .notPermitted)
    }

    func testCacheIsPrunedToLimit() async throws {
        runner.result = .success(.data(pngData(size: 1)))
        let fetcher = fetcher()
        for index in 0..<(ArtworkFetcher.cacheLimit + 5) {
            _ = await fetcher.artwork(for: makeTrack("t\(index)", .music))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        XCTAssertEqual(files.count, ArtworkFetcher.cacheLimit)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'AppleScriptRunning'`.

- [ ] **Step 3: Implement**

`AppleScriptRunner.swift`:

```swift
import AppKit
import Foundation

enum ScriptValue: Equatable, Sendable {
    case text(String)
    case data(Data)
    case none
}

enum ScriptError: Error, Equatable {
    /// The user said no to "Perch wants to control …" (errAEEventNotPermitted).
    case notPermitted
    case failed(Int)
}

protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async throws -> ScriptValue
}

/// Runs scripts one at a time on a private serial queue. `NSAppleScript` is
/// not thread-safe, but is fine confined to a single thread, and a slow
/// player must not block the main thread.
final class NSAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.ahlab.perch.spin.applescript")

    func run(_ source: String) async throws -> ScriptValue {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: ScriptError.failed(0))
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    continuation.resume(throwing: code == -1743 ? ScriptError.notPermitted : ScriptError.failed(code))
                    return
                }
                continuation.resume(returning: Self.value(of: result))
            }
        }
    }

    private static func value(of descriptor: NSAppleEventDescriptor) -> ScriptValue {
        switch descriptor.descriptorType {
        case DescType(typeNull):
            return .none
        case DescType(typeUnicodeText), DescType(typeUTF8Text), DescType(typeChar):
            return .text(descriptor.stringValue ?? "")
        default:
            return descriptor.data.isEmpty ? .none : .data(descriptor.data)
        }
    }
}

enum PlayerProcess {
    /// An Apple Event to a quit app launches it, so every script is gated on this.
    static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }
}
```

`PlayerScripts.swift`:

```swift
import Foundation

enum PlayerScripts {
    /// Returns `state` alone when stopped, otherwise state, title, artist,
    /// album and id on separate lines.
    static func state(of player: Player) -> String {
        let idProperty = player == .spotify ? "id" : "persistent ID"
        return """
        tell application "\(player.scriptName)"
            set s to player state as string
            if s is "stopped" then return s
            set t to current track
            return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (\(idProperty) of t)
        end tell
        """
    }

    /// Asks for the art only if the player is still on `track`, so a skip
    /// between the notification and the script cannot file one track's art
    /// under another's id.
    static func artwork(of track: Track) -> String {
        let id = track.id.filter { $0 != "\"" && $0 != "\\" }
        switch track.player {
        case .spotify:
            return """
            tell application "Spotify"
                if id of current track is "\(id)" then return artwork url of current track
            end tell
            """
        case .music:
            return """
            tell application "Music"
                if persistent ID of current track is "\(id)" then return data of artwork 1 of current track
            end tell
            """
        }
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
    var isRunning: @Sendable (Player) -> Bool = PlayerProcess.isRunning

    func event(for player: Player) async -> PlayerEvent? {
        guard isRunning(player),
              case .text(let text)? = try? await runner.run(PlayerScripts.state(of: player))
        else { return nil }
        return PlayerScripts.parseState(text, player: player)
    }
}
```

`ArtworkFetcher.swift`:

```swift
import Foundation

enum ArtworkResult: Equatable, Sendable {
    case image(Data)
    case none
    case notPermitted
}

protocol ArtworkProviding: Sendable {
    func artwork(for track: Track) async -> ArtworkResult
}

/// Album art for a track: from disk if seen before, otherwise from the player.
actor ArtworkFetcher: ArtworkProviding {
    static let cacheLimit = 50

    private let runner: AppleScriptRunning
    private let cacheDirectory: URL
    private let isRunning: @Sendable (Player) -> Bool
    private let download: @Sendable (URL) async throws -> Data

    init(
        runner: AppleScriptRunning,
        cacheDirectory: URL,
        isRunning: @escaping @Sendable (Player) -> Bool = PlayerProcess.isRunning,
        download: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.runner = runner
        self.cacheDirectory = cacheDirectory
        self.isRunning = isRunning
        self.download = download
    }

    func artwork(for track: Track) async -> ArtworkResult {
        let file = cacheURL(for: track)
        if let data = try? Data(contentsOf: file) { return .image(data) }
        guard isRunning(track.player) else { return .none }

        let value: ScriptValue
        do {
            value = try await runner.run(PlayerScripts.artwork(of: track))
        } catch ScriptError.notPermitted {
            return .notPermitted
        } catch {
            return .none
        }

        let data: Data
        switch value {
        case .data(let bytes):
            data = bytes
        case .text(let string):
            guard let url = URL(string: string), url.scheme == "https",
                  let bytes = try? await download(url)
            else { return .none }
            data = bytes
        case .none:
            return .none
        }
        guard !data.isEmpty else { return .none }
        store(data, at: file)
        return .image(data)
    }

    private func cacheURL(for track: Track) -> URL {
        let safe = String((track.player.rawValue + "-" + track.id).map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return cacheDirectory.appendingPathComponent(safe)
    }

    private func store(_ data: Data, at file: URL) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        prune()
    }

    /// Keeps the newest `cacheLimit` files.
    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: keys
        ), files.count > Self.cacheLimit else { return }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
        }
        for url in files.sorted(by: { modified($0) > modified($1) }).dropFirst(Self.cacheLimit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "Executed|error:"`
Expected: 0 failures. If `typeUnicodeText` etc. are unresolved, add `import CoreServices` to `AppleScriptRunner.swift`.

- [ ] **Step 5: Smoke-test the real scripts (unsandboxed, from the shell)**

With Spotify playing, run the same AppleScript the code sends:

```bash
osascript -e 'tell application "Spotify"' -e 'set t to current track' -e 'return (player state as string) & linefeed & (name of t) & linefeed & (id of t)' -e 'end tell'
osascript -e 'tell application "Spotify" to return artwork url of current track'
```

Expected: state, title and a `spotify:track:…` id; then an `https://i.scdn.co/…` URL. If Music has a playing track, `osascript -e 'tell application "Music" to return persistent ID of current track'` prints 16 hex digits.

- [ ] **Step 6: Commit**

```bash
git add Plugins/SpinPlugin
git commit -m "feat(spin): Apple Events for player state and album art, with a disk cache"
```

---

### Task 6: `SpinModel` and `NowPlayingSource`

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Store/SpinModel.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/NowPlaying/NowPlayingSource.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SpinModelTests.swift`
- Modify: `Plugins/SpinPlugin/Tests/SpinPluginTests/SpinTestSupport.swift`

**Interfaces:**
- Consumes: `NowPlayingTracker` (Task 2), `SceneVisibility`, `SpinMotion` (Task 3), `SceneAsset` (Task 4), `ArtworkProviding`, `ArtworkResult`, `PlayerQuerying` (Task 5), `PluginDefaults` (PerchKit).
- Produces:
  - `@MainActor @Observable public final class SpinModel` with: `nowPlaying: PlayerEvent?`, `artwork: NSImage?`, `artworkStatus: ArtworkStatus` (`.none/.loading/.loaded/.notPermitted`), `phase: SceneVisibility.Phase`, `motion: SpinMotion`, `isAnimating: Bool`, `isScreenAsleep: Bool` (settable), `scenes: [SceneAsset]`, `selectedSceneID: String` (settable, persisted as `scene`), `showsScene: Bool` (settable, persisted as `showsScene`, default `false`), `selectedScene: SceneAsset?`, `wantsWindow: Bool`; methods `receive(_ event: PlayerEvent)`, `refresh(_ player: Player)`, `activate()`, `reset()`, `reevaluate()`; test hook `settle() async`.
  - `@MainActor final class NowPlayingSource { var onEvent: ((PlayerEvent) -> Void)?; var onPing: ((Player) -> Void)?; func start(); func stop() }`.

- [ ] **Step 1: Add fakes**

Append to `SpinTestSupport.swift`:

```swift
/// Artwork per track id, optionally after a delay.
final class FakeArtwork: ArtworkProviding, @unchecked Sendable {
    var results: [String: ArtworkResult] = [:]
    var delays: [String: Duration] = [:]

    func artwork(for track: Track) async -> ArtworkResult {
        if let delay = delays[track.id] { try? await Task.sleep(for: delay) }
        return results[track.id] ?? .none
    }
}

final class FakeQuery: PlayerQuerying, @unchecked Sendable {
    var events: [Player: PlayerEvent] = [:]
    private(set) var asked: [Player] = []

    func event(for player: Player) async -> PlayerEvent? {
        asked.append(player)
        return events[player]
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
@testable import SpinPlugin
import PerchKit
import XCTest

@MainActor
final class SpinModelTests: XCTestCase {
    private var suite: UserDefaults!
    private let artwork = FakeArtwork()
    private let query = FakeQuery()
    private let clock = TestClock()
    private let scene = SceneAsset(
        descriptor: SceneDescriptor(
            id: "room", name: "Room", order: 0,
            platter: .init(x: 0.5, y: 0.5, radius: 0.1, squash: 0.4), tonearm: nil,
            sleeve: .init(x: 0.2, y: 0.5, size: 0.2, rotation: 0, style: .stand)
        ),
        backgroundURL: URL(fileURLWithPath: "/dev/null"), thumbnailURL: URL(fileURLWithPath: "/dev/null")
    )

    override func setUp() {
        suite = UserDefaults(suiteName: UUID().uuidString)
    }

    private func model(showsScene: Bool = true) -> SpinModel {
        let defaults = PluginDefaults(suite: suite, prefix: "spin")
        defaults.set(showsScene, for: "showsScene")
        let clock = clock
        return SpinModel(defaults: defaults, scenes: [scene], artworkProvider: artwork, query: query, now: { clock.now })
    }

    private func playing(_ id: String) -> PlayerEvent {
        PlayerEvent(player: .spotify, state: .playing, track: makeTrack(id))
    }

    private func paused(_ id: String) -> PlayerEvent {
        PlayerEvent(player: .spotify, state: .paused, track: makeTrack(id))
    }

    func testShowsSceneDefaultsOff() {
        let model = SpinModel(defaults: PluginDefaults(suite: suite, prefix: "fresh"), scenes: [scene],
                              artworkProvider: artwork, query: query)
        XCTAssertFalse(model.showsScene)
        model.receive(playing("a"))
        XCTAssertFalse(model.wantsWindow)
    }

    func testPlayingShowsSpinningScene() async {
        let model = model()
        model.receive(playing("a"))
        XCTAssertEqual(model.phase, .spinning)
        XCTAssertTrue(model.wantsWindow)
        XCTAssertTrue(model.isAnimating)
    }

    func testPauseRestsThenHidesAfterLinger() {
        let model = model()
        model.receive(playing("a"))
        clock.advance(3600)
        model.receive(paused("a"))
        XCTAssertEqual(model.phase, .resting)
        clock.advance(SceneVisibility.linger + 1)
        model.reevaluate()
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.wantsWindow)
    }

    func testArtworkLoadsForTrack() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .loaded)
        XCTAssertEqual(model.artwork?.representations.first?.pixelsWide, 3)
    }

    /// Review Focus 2.
    func testStaleArtworkIsDiscarded() async {
        artwork.results["a"] = .image(pngData(size: 2))
        artwork.delays["a"] = .milliseconds(200)
        artwork.results["b"] = .image(pngData(size: 5))
        let model = model()
        model.receive(playing("a"))
        model.receive(playing("b"))
        await model.settle()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.artwork?.representations.first?.pixelsWide, 5)
    }

    /// Review Focus 3.
    func testNotPermittedStatus() async {
        artwork.results["a"] = .notPermitted
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .notPermitted)
        XCTAssertNil(model.artwork)
    }

    func testNoScriptingWhileSceneIsOff() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model(showsScene: false)
        model.receive(playing("a"))
        model.activate()
        await model.settle()
        XCTAssertNil(model.artwork)
        XCTAssertTrue(query.asked.isEmpty)
    }

    func testTurningSceneOnFetchesArtAndPrimes() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model(showsScene: false)
        model.receive(playing("a"))
        model.showsScene = true
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .loaded)
        XCTAssertEqual(Set(query.asked), Set(Player.allCases))
    }

    func testActivatePrimesFromRunningPlayers() async {
        query.events[.music] = PlayerEvent(player: .music, state: .playing, track: makeTrack("m", .music))
        let model = model()
        model.activate()
        await model.settle()
        XCTAssertEqual(model.nowPlaying?.player, .music)
    }

    func testPingRefreshesFromQuery() async {
        query.events[.spotify] = playing("z")
        let model = model()
        model.refresh(.spotify)
        await model.settle()
        XCTAssertEqual(model.nowPlaying?.track?.id, "z")
    }

    /// Review Focus 5.
    func testTogglingSceneOffHidesWindow() {
        let model = model()
        model.receive(playing("a"))
        model.showsScene = false
        XCTAssertFalse(model.wantsWindow)
    }

    /// Review Focus 5.
    func testResetClearsEverything() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        model.reset()
        XCTAssertNil(model.nowPlaying)
        XCTAssertNil(model.artwork)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.wantsWindow)
    }

    func testSelectedScenePersists() {
        let first = model()
        first.selectedSceneID = "room"
        XCTAssertEqual(model().selectedSceneID, "room")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --package-path Plugins/SpinPlugin --filter SpinModelTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SpinModel'`.

- [ ] **Step 4: Implement `SpinModel.swift`**

```swift
import AppKit
import Observation
import PerchKit

/// Everything Spin knows, and every decision it makes, minus the window.
@MainActor
@Observable
public final class SpinModel {
    public enum ArtworkStatus: Equatable, Sendable {
        case none
        case loading
        case loaded
        case notPermitted
    }

    public private(set) var nowPlaying: PlayerEvent?
    public private(set) var artwork: NSImage?
    public private(set) var artworkStatus: ArtworkStatus = .none
    private(set) var phase: SceneVisibility.Phase = .hidden
    private(set) var motion = SpinMotion()
    /// Whether the record's animation clock needs to tick: spinning, or still
    /// easing to a stop.
    public private(set) var isAnimating = false
    /// Set by the plugin while the display sleeps or the session is locked.
    public var isScreenAsleep = false

    let scenes: [SceneAsset]

    public var selectedSceneID: String {
        didSet { defaults.set(selectedSceneID, for: Key.scene) }
    }

    /// Off until the user turns it on: this is what triggers the Automation
    /// prompt and takes over the desktop, so neither happens unasked.
    public var showsScene: Bool {
        didSet {
            defaults.set(showsScene, for: Key.showsScene)
            guard showsScene, !oldValue else { return }
            if let track = nowPlaying?.track { loadArtwork(for: track) }
            prime()
        }
    }

    var selectedScene: SceneAsset? {
        scenes.first { $0.id == selectedSceneID } ?? scenes.first
    }

    var wantsWindow: Bool {
        showsScene && phase != .hidden && selectedScene != nil
    }

    private enum Key {
        static let scene = "scene"
        static let showsScene = "showsScene"
    }

    @ObservationIgnored private let defaults: PluginDefaults
    @ObservationIgnored private let artworkProvider: ArtworkProviding
    @ObservationIgnored private let query: PlayerQuerying
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tracker = NowPlayingTracker()
    @ObservationIgnored private var lastPlayingAt: Date?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var queryTasks: [Task<Void, Never>] = []

    init(
        defaults: PluginDefaults,
        scenes: [SceneAsset],
        artworkProvider: ArtworkProviding,
        query: PlayerQuerying,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.scenes = scenes
        self.artworkProvider = artworkProvider
        self.query = query
        self.now = now
        selectedSceneID = defaults.string(Key.scene) ?? scenes.first?.id ?? ""
        showsScene = defaults.bool(Key.showsScene, default: false)
    }

    // MARK: Inputs

    public func receive(_ event: PlayerEvent) {
        let wasPlaying = nowPlaying?.state == .playing
        guard tracker.apply(event) else { return }
        let current = tracker.current
        let previousTrack = nowPlaying?.track
        nowPlaying = current

        let time = now()
        // Review Focus 1: stamp the end of playback too, so the linger
        // counts from when the music stopped.
        if current?.state == .playing || wasPlaying { lastPlayingAt = time }

        // A stop carries no track; the last art stays up while the scene lingers.
        if let track = current?.track, track != previousTrack {
            loadArtwork(for: track)
        }

        let isPlaying = current?.state == .playing
        motion.setPlaying(isPlaying, at: time)
        updateAnimating(isPlaying)
        reevaluate()
    }

    /// A player posted a notification we could not read; ask it directly.
    public func refresh(_ player: Player) {
        guard showsScene else { return }
        let query = query
        queryTasks.append(Task { [weak self] in
            guard let event = await query.event(for: player) else { return }
            self?.receive(event)
        })
    }

    /// Called when the plugin is enabled.
    public func activate() { prime() }

    /// Called when the plugin is disabled: forget everything, cancel everything.
    public func reset() {
        artworkTask?.cancel()
        lingerTask?.cancel()
        settleTask?.cancel()
        queryTasks.forEach { $0.cancel() }
        queryTasks = []
        tracker = NowPlayingTracker()
        nowPlaying = nil
        artwork = nil
        artworkStatus = .none
        lastPlayingAt = nil
        motion = SpinMotion()
        isAnimating = false
        phase = .hidden
    }

    func reevaluate() {
        phase = SceneVisibility.phase(state: nowPlaying?.state, lastPlayingAt: lastPlayingAt, now: now())
        scheduleLinger()
    }

    /// Test hook: wait for in-flight artwork and query work.
    func settle() async {
        for task in queryTasks { await task.value }
        await artworkTask?.value
    }

    // MARK: Work

    private func prime() {
        guard showsScene else { return }
        for player in Player.allCases { refresh(player) }
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        artwork = nil
        guard showsScene else {
            artworkStatus = .none
            return
        }
        artworkStatus = .loading
        let provider = artworkProvider
        artworkTask = Task { [weak self] in
            let result = await provider.artwork(for: track)
            guard !Task.isCancelled, let self, self.nowPlaying?.track == track else { return }
            switch result {
            case .image(let data):
                self.artwork = NSImage(data: data)
                self.artworkStatus = self.artwork == nil ? .none : .loaded
            case .none:
                self.artworkStatus = .none
            case .notPermitted:
                self.artworkStatus = .notPermitted
            }
        }
    }

    private func updateAnimating(_ isPlaying: Bool) {
        settleTask?.cancel()
        if isPlaying {
            isAnimating = true
            return
        }
        guard isAnimating else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SpinMotion.spinDown + 0.1))
            guard !Task.isCancelled, let self, self.nowPlaying?.state != .playing else { return }
            self.isAnimating = false
        }
    }

    private func scheduleLinger() {
        lingerTask?.cancel()
        guard phase == .resting, let lastPlayingAt else { return }
        let delay = max(0, lastPlayingAt.addingTimeInterval(SceneVisibility.linger).timeIntervalSince(now()))
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.1))
            guard !Task.isCancelled else { return }
            self?.reevaluate()
        }
    }
}
```

Note: `settle()` awaits `settleTask`? No — it is a 1.6 s timer; tests that need `isAnimating == false` are not part of this suite.

- [ ] **Step 5: Implement `NowPlayingSource.swift`**

```swift
import AppKit

/// Listens to both players' distributed notifications, and to them quitting.
///
/// Receiving a distributed notification needs no permission and works from
/// the sandbox. A notification whose payload does not parse (for example if
/// the sandbox strips userInfo) is passed on as a ping, so the model can ask
/// the player directly.
@MainActor
final class NowPlayingSource {
    var onEvent: ((PlayerEvent) -> Void)?
    var onPing: ((Player) -> Void)?

    private var distributedTokens: [NSObjectProtocol] = []
    private var workspaceToken: NSObjectProtocol?

    func start() {
        guard distributedTokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            let token = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let event = PlayerNotification.parse(name: note.name, userInfo: note.userInfo)
                MainActor.assumeIsolated {
                    if let event { self?.onEvent?(event) } else { self?.onPing?(player) }
                }
            }
            distributedTokens.append(token)
        }
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = Player.allCases.first(where: { $0.bundleIdentifier == app?.bundleIdentifier }) else { return }
            MainActor.assumeIsolated {
                self?.onEvent?(PlayerEvent(player: player, state: .stopped, track: nil))
            }
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for token in distributedTokens { center.removeObserver(token) }
        distributedTokens = []
        if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }
        workspaceToken = nil
    }
}
```

- [ ] **Step 6: Run to verify pass**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "Executed|error:|failed"`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Plugins/SpinPlugin
git commit -m "feat(spin): model and now-playing source"
```

---

### Task 7: Generate and place the two scenes

**Files:**
- Create: `scripts/generate_scene.py`
- Create: `scripts/scene_overlay.py`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/listening-room/{background.jpg,thumb.jpg,scene.json}`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/after-hours/{background.jpg,thumb.jpg,scene.json}`
- Delete: `Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/.gitkeep`
- Modify: `Plugins/SpinPlugin/Tests/SpinPluginTests/SceneCatalogTests.swift`

**Interfaces:**
- Consumes: the `scene.json` schema and geometry conventions of Task 4.
- Produces: `SceneCatalog.builtIn` returns `[listening-room (order 1), after-hours (order 2)]`.

- [ ] **Step 1: Write the built-in catalogue test (fails: no scenes yet)**

Append to `SceneCatalogTests`:

```swift
    func testBuiltInScenesShipAndDecode() {
        let scenes = SceneCatalog.builtIn
        XCTAssertEqual(scenes.map(\.id), ["listening-room", "after-hours"])
        for scene in scenes {
            XCTAssertNotNil(NSImage(contentsOf: scene.backgroundURL), scene.id)
            XCTAssertNotNil(NSImage(contentsOf: scene.thumbnailURL), scene.id)
        }
    }
```

(add `import AppKit` at the top). Run `swift test --package-path Plugins/SpinPlugin --filter testBuiltInScenesShipAndDecode` — expected FAIL, empty array.

- [ ] **Step 2: Write `scripts/generate_scene.py`**

```python
#!/usr/bin/env python3
"""Generate an empty-room background for the Spin plugin with Gemini.

Usage: GEMINI_API_KEY=... scripts/generate_scene.py <out.jpg> "<prompt>" [model]

The photo must not contain a record, album art or text: the plugin draws
those. Only the prompt leaves this machine.
"""
import base64, json, os, sys, urllib.request

COMMON = (
    " Photorealistic interior photograph, eye level slightly above a desk, 16:9, "
    "shot on a 35mm lens, shallow depth of field on the far wall only. "
    "A minimalist turntable sits on the desk with an EMPTY platter: no vinyl record on it "
    "and no tonearm visible. Nothing on the desk has any text, logo, label or artwork. "
    "No people, no screens."
)

def main():
    out, prompt = sys.argv[1], sys.argv[2]
    model = sys.argv[3] if len(sys.argv) > 3 else "gemini-3-pro-image"
    body = {
        "contents": [{"parts": [{"text": prompt + COMMON}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": "16:9", "imageSize": "4K"},
        },
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    req = urllib.request.Request(url, json.dumps(body).encode(), {
        "Content-Type": "application/json", "x-goog-api-key": os.environ["GEMINI_API_KEY"],
    })
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.load(resp)
    for part in data["candidates"][0]["content"]["parts"]:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline:
            with open(out, "wb") as f:
                f.write(base64.b64decode(inline["data"]))
            print(out)
            return
    sys.exit("no image in response: " + json.dumps(data)[:500])

if __name__ == "__main__":
    main()
```

If the API rejects `imageSize`, delete that key and retry; a 1344×768 result is acceptable for v1 (to be swapped later).

- [ ] **Step 3: Generate both photos**

```bash
mkdir -p Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/{listening-room,after-hours}
python3 scripts/generate_scene.py /tmp/listening-room.png "A calm listening room in late-morning daylight. Warm wood desk spanning the frame, soft window light casting long diagonal shadows across a cream wall, a framed botanical print high on the wall. The turntable sits centre-right on the desk. To its left, an empty light-oak picture ledge stand on the desk, holding nothing."
python3 scripts/generate_scene.py /tmp/after-hours.png "The same kind of desk at night, lit only by a warm glass table lamp on the right, deep amber glow on the wall, a dark framed still-life painting above. The turntable sits centre on the desk. To its left, an empty dark-walnut picture ledge stand holding nothing; to the right, clear desk space."
```

Open each with the Read tool. Reject and regenerate (up to 4 tries each) if: a record is on the platter, there is text/logos, the platter is not clearly visible, or the stand holds something. A visible tonearm is acceptable — then that scene's `scene.json` omits `tonearm`.

Convert and thumbnail:

```bash
for s in listening-room after-hours; do
  d=Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/$s
  sips -s format jpeg -s formatOptions 85 /tmp/$s.png --out $d/background.jpg
  sips -Z 2880 $d/background.jpg
  sips -Z 480 $d/background.jpg --out $d/thumb.jpg
done
rm Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes/.gitkeep
```

- [ ] **Step 4: Write `scripts/scene_overlay.py` for placement tuning**

```python
#!/usr/bin/env python3
"""Draw a scene.json's record, tonearm and sleeve over its background.

Usage: scripts/scene_overlay.py <scene folder> <out.png>
Mirrors SceneLayout's conventions: fractions of the image, origin top-left,
lengths as fractions of width, tonearm 0° = straight down, positive = tip left.
"""
import json, math, sys
from PIL import Image, ImageDraw

folder, out = sys.argv[1], sys.argv[2]
scene = json.load(open(f"{folder}/scene.json"))
img = Image.open(f"{folder}/background.jpg").convert("RGB")
w, h = img.size
d = ImageDraw.Draw(img)
p = scene["platter"]
cx, cy, r = p["x"] * w, p["y"] * h, p["radius"] * w
ry = r * p["squash"]
d.ellipse([cx - r, cy - ry, cx + r, cy + ry], outline=(255, 0, 0), width=4)
d.ellipse([cx - r * .36, cy - ry * .36, cx + r * .36, cy + ry * .36], outline=(255, 255, 0), width=3)
arm = scene.get("tonearm")
if arm:
    px, py, length = arm["pivotX"] * w, arm["pivotY"] * h, arm["length"] * w
    for angle, colour in ((arm["restAngle"], (0, 128, 255)), (arm["playAngle"], (0, 255, 0))):
        t = math.radians(angle)
        d.line([px, py, px - length * math.sin(t), py + length * math.cos(t)], fill=colour, width=5)
s = scene["sleeve"]
sx, sy, half = s["x"] * w, s["y"] * h, s["size"] * w / 2
d.rectangle([sx - half, sy - half, sx + half, sy + half], outline=(255, 0, 255), width=4)
img.save(out)
print(out)
```

- [ ] **Step 5: Write each `scene.json`, then tune by eye**

Start `listening-room/scene.json` from (replace with estimates read off the actual photo):

```json
{
  "id": "listening-room",
  "name": "Listening Room",
  "order": 1,
  "platter": { "x": 0.55, "y": 0.66, "radius": 0.11, "squash": 0.42 },
  "tonearm": { "pivotX": 0.66, "pivotY": 0.58, "length": 0.13, "restAngle": 5, "playAngle": 28 },
  "sleeve": { "x": 0.24, "y": 0.52, "size": 0.17, "rotation": -2, "style": "stand" }
}
```

`after-hours/scene.json`: same shape, `"id": "after-hours"`, `"name": "After Hours"`, `"order": 2`.

Loop: `python3 scripts/scene_overlay.py <folder> /tmp/overlay.png`, view with the Read tool, adjust numbers, repeat until the red ellipse sits on the platter's rim, the yellow ellipse is a plausible label, the green arm line lands on the record's outer third, and the magenta square sits in the stand. Measure `squash` as (platter's visible height ÷ visible width).

- [ ] **Step 6: Run the catalogue test**

Run: `swift test --package-path Plugins/SpinPlugin --filter SceneCatalogTests 2>&1 | grep Executed`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add scripts/generate_scene.py scripts/scene_overlay.py Plugins/SpinPlugin
git commit -m "feat(spin): Listening Room and After Hours scenes"
```

---

### Task 8: Views, desktop window, the plugin, host wiring

**Files:**
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Views/RecordView.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Views/TonearmView.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Views/SleeveView.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Views/SceneView.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Views/SpinPanelView.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Desktop/DesktopSceneController.swift`
- Create: `Plugins/SpinPlugin/Sources/SpinPlugin/Spin.swift`
- Create: `Plugins/SpinPlugin/Tests/SpinPluginTests/SpinPluginTests.swift`
- Modify: `project.yml` (packages list, `Perch` dependencies, `PerchTests` dependencies, `Perch` `info.properties`)
- Modify: `Perch/Perch.entitlements`
- Modify: `Perch/PerchApp.swift:1-12` (import) and `:46-57` (`makePlugins`)

**Interfaces:**
- Consumes: `SpinModel` and everything it exposes (Task 6), `SceneLayout`/`SceneFrames`/`TonearmFrame`/`SceneAsset` (Task 4), `SpinMotion` (Task 3), `NowPlayingSource` (Task 6), `NSAppleScriptRunner`, `ArtworkFetcher`, `ScriptedPlayerQuery` (Task 5).
- Produces: `public final class Spin: PerchPlugin` with `identifier = "org.ahlab.perch.spin"`, `displayName = "Spin"`, `icon = "record.circle"`, `capabilities = [.network, .media]`; testable `init(context:scenes:artwork:query:)`.

- [ ] **Step 1: Write the failing plugin tests**

```swift
@testable import SpinPlugin
import PerchKit
import XCTest

@MainActor
final class SpinPluginTests: XCTestCase {
    private func makeSpin() -> Spin {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = PluginContext(
            storage: PluginStorage(directory: dir),
            defaults: PluginDefaults(suite: UserDefaults(suiteName: UUID().uuidString)!, prefix: Spin.identifier)
        )
        return Spin(context: context, scenes: SceneCatalog.builtIn, artwork: FakeArtwork(), query: FakeQuery())
    }

    func testMetadata() {
        XCTAssertEqual(Spin.identifier, "org.ahlab.perch.spin")
        XCTAssertEqual(Spin.displayName, "Spin")
        XCTAssertEqual(Spin.capabilities, [.network, .media])
    }

    func testMenuBarShowsTrackOnlyWhilePlaying() {
        let spin = makeSpin()
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle"))
        spin.model.receive(PlayerEvent(player: .spotify, state: .playing, track: makeTrack("a")))
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle", text: "Title a – Artist"))
        spin.model.receive(PlayerEvent(player: .spotify, state: .paused, track: makeTrack("a")))
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle"))
    }

    func testDisablingResetsTheModel() {
        let spin = makeSpin()
        spin.setEnabled(true)
        spin.model.receive(PlayerEvent(player: .spotify, state: .playing, track: makeTrack("a")))
        spin.setEnabled(false)
        XCTAssertNil(spin.model.nowPlaying)
    }
}
```

Run `swift test --package-path Plugins/SpinPlugin --filter SpinPluginTests` — expected: `cannot find 'Spin'`.

- [ ] **Step 2: Write the record, tonearm and sleeve views**

`RecordView.swift`:

```swift
import SwiftUI

/// A record seen from above at an angle: grooved disc, album-art label,
/// static sheen. Only the disc and label turn; light does not.
struct RecordView: View {
    let artwork: NSImage?
    let fallbackTitle: String
    let radius: CGFloat
    let squash: CGFloat
    let motion: SpinMotion
    let animate: Bool

    var body: some View {
        TimelineView(.animation(paused: !animate)) { context in
            ZStack {
                ZStack {
                    Circle().fill(Color(white: 0.05))
                    ForEach(1..<16) { ring in
                        Circle()
                            .stroke(Color.white.opacity(ring.isMultiple(of: 4) ? 0.07 : 0.03), lineWidth: 1)
                            .padding(radius * (0.38 + CGFloat(ring) * 0.035))
                    }
                    label
                        .frame(width: radius * 0.72, height: radius * 0.72)
                        .clipShape(Circle())
                    Circle().fill(Color(white: 0.75)).frame(width: radius * 0.04, height: radius * 0.04)
                }
                .rotationEffect(.degrees(motion.angle(at: context.date)))
                Circle()
                    .fill(AngularGradient(
                        colors: [.clear, .white.opacity(0.12), .clear, .clear, .white.opacity(0.08), .clear],
                        center: .center
                    ))
                    .blendMode(.screen)
            }
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(x: 1, y: squash)
            .shadow(color: .black.opacity(0.45), radius: radius * 0.05, y: radius * 0.03)
        }
    }

    @ViewBuilder private var label: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(red: 0.62, green: 0.18, blue: 0.16)
                Text(fallbackTitle)
                    .font(.system(size: max(6, radius * 0.06), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(radius * 0.08)
            }
        }
    }
}
```

`TonearmView.swift`:

```swift
import SwiftUI

/// A slim arm hinged at its pivot. Angle 0 points straight down; positive
/// swings the tip left, which is SwiftUI's clockwise rotation.
struct TonearmView: View {
    let frame: TonearmFrame
    let isPlaying: Bool

    var body: some View {
        let width = max(3, frame.length * 0.028)
        VStack(spacing: 0) {
            Capsule().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: frame.length)
            RoundedRectangle(cornerRadius: width * 0.4)
                .fill(Color(white: 0.2))
                .frame(width: width * 3, height: width * 4)
        }
        .rotationEffect(.degrees(isPlaying ? frame.playAngle : frame.restAngle), anchor: .top)
        .animation(.easeInOut(duration: 1.2), value: isPlaying)
        .shadow(color: .black.opacity(0.4), radius: width, x: width, y: width)
        .overlay(alignment: .top) {
            Circle().fill(Color(white: 0.3)).frame(width: width * 5, height: width * 5).offset(y: -width * 2.5)
        }
        .frame(width: frame.length * 0.2, height: frame.length * 2, alignment: .top)
        .position(x: frame.pivot.x, y: frame.pivot.y + frame.length)
    }
}
```

`SleeveView.swift`:

```swift
import SwiftUI

struct SleeveView: View {
    let artwork: NSImage?
    let title: String
    let size: CGFloat
    let rotation: Double
    let style: SceneDescriptor.Sleeve.Style

    var body: some View {
        cover
            .frame(width: size, height: size)
            .clipped()
            .overlay(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
            .rotation3DEffect(.degrees(style == .flat ? 58 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.4), radius: size * 0.03, x: size * 0.015, y: size * 0.02)
    }

    @ViewBuilder private var cover: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Text(title).font(.system(size: size * 0.07, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(size * 0.1)
            }
        }
    }
}
```

- [ ] **Step 3: Write `SceneView.swift`**

```swift
import SwiftUI

/// The whole desktop scene for the selected scene and current track.
struct SceneView: View {
    let model: SpinModel
    let background: NSImage

    var body: some View {
        GeometryReader { geometry in
            if let scene = model.selectedScene {
                let frames = SceneLayout.frames(for: scene.descriptor, imageSize: background.size, in: geometry.size)
                let title = model.nowPlaying?.track?.title ?? ""
                let isPlaying = model.nowPlaying?.state == .playing
                ZStack(alignment: .topLeading) {
                    Image(nsImage: background)
                        .resizable()
                        .frame(width: frames.imageRect.width, height: frames.imageRect.height)
                        .position(x: frames.imageRect.midX, y: frames.imageRect.midY)
                    SleeveView(artwork: model.artwork, title: title, size: frames.sleeveSize,
                               rotation: frames.sleeveRotation, style: scene.descriptor.sleeve.style)
                        .position(frames.sleeveCenter)
                    RecordView(artwork: model.artwork, fallbackTitle: title, radius: frames.platterRadius,
                               squash: frames.squash, motion: model.motion,
                               animate: model.isAnimating && !model.isScreenAsleep)
                        .position(frames.platterCenter)
                    if let arm = frames.tonearm {
                        TonearmView(frame: arm, isPlaying: isPlaying)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: model.artwork)
            }
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 4: Write `DesktopSceneController.swift`**

```swift
import AppKit
import SwiftUI

/// Owns the desktop-level window. It exists only while the model wants it,
/// and fades in and out rather than popping.
@MainActor
final class DesktopSceneController {
    private let model: SpinModel
    private var window: NSWindow?
    private var screenToken: NSObjectProtocol?
    private var generation = 0
    private var shownSceneID: String?
    private var backgrounds: [String: NSImage] = [:]
    private var running = false

    init(model: SpinModel) {
        self.model = model
    }

    func start() {
        running = true
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        }
        observe()
    }

    func stop() {
        running = false
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        window?.orderOut(nil)
        window = nil
        shownSceneID = nil
    }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update() {
        if model.wantsWindow, let scene = model.selectedScene { show(scene) } else { hide() }
    }

    private func background(for scene: SceneAsset) -> NSImage? {
        if let cached = backgrounds[scene.id] { return cached }
        let image = NSImage(contentsOf: scene.backgroundURL)
        backgrounds[scene.id] = image
        return image
    }

    private func show(_ scene: SceneAsset) {
        guard let screen = NSScreen.screens.first, let background = background(for: scene) else { return }
        generation += 1
        // update() re-runs on every phase change; only rebuild the view for a new scene.
        let content = { NSHostingView(rootView: SceneView(model: self.model, background: background)) }
        if let window {
            if shownSceneID != scene.id { window.contentView = content() }
        } else {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            // Just above the wallpaper, below the desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = content()
            window.orderFront(nil)
            self.window = window
        }
        shownSceneID = scene.id
        window?.setFrame(screen.frame, display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            window?.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let window else { return }
        generation += 1
        let fading = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() during the fade bumped the generation; keep the window.
                guard let self, self.generation == fading else { return }
                self.window?.orderOut(nil)
                self.window = nil
                self.shownSceneID = nil
            }
        }
    }

    private func fitToScreen() {
        guard let window, let screen = NSScreen.screens.first else { return }
        window.setFrame(screen.frame, display: true)
    }
}
```

Note: `update()` runs inside `withObservationTracking`, so it re-runs when anything it reads changes (`wantsWindow` reads `showsScene`, `phase`, `selectedSceneID`). `SceneView` observes the model itself; the controller only creates, swaps and fades the window.

- [ ] **Step 5: Write `SpinPanelView.swift`**

```swift
import SwiftUI

struct SpinPanelView: View {
    @Bindable var model: SpinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nowPlaying
            Toggle("Show scene on desktop", isOn: $model.showsScene)
                .toggleStyle(.switch)
            if !model.showsScene {
                Text("Turn this on and the desktop becomes a turntable while Spotify or Music plays. macOS will ask once to let Perch read each player.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.artworkStatus == .notPermitted {
                HStack {
                    Text("Perch isn't allowed to read album art.").font(.caption)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .controlSize(.small)
                }
            }
            scenePicker
        }
        .padding(14)
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "record.circle").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                if let event = model.nowPlaying, let track = event.track {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text("\(track.artist) · \(event.player.displayName)\(event.state == .playing ? "" : " · \(event.state.rawValue.capitalized)")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Nothing playing").font(.headline)
                    Text("Play something in Spotify or Music").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scenePicker: some View {
        HStack(spacing: 10) {
            ForEach(model.scenes) { scene in
                Button {
                    model.selectedSceneID = scene.id
                } label: {
                    VStack(spacing: 4) {
                        AsyncImage(url: scene.thumbnailURL) { image in
                            image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                        } placeholder: {
                            Color.secondary.opacity(0.2)
                        }
                        .frame(width: 120, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(model.selectedScene?.id == scene.id ? Color.accentColor : .clear, lineWidth: 2))
                        Text(scene.descriptor.name).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 6: Write `Spin.swift`**

```swift
import AppKit
import Observation
import PerchKit
import SwiftUI

/// While Spotify or Music plays, the desktop becomes a room with a turntable
/// spinning the album.
///
/// Declares `.network` to download Spotify's artwork, and `.media` because it
/// reads what the user is listening to over Apple Events.
@MainActor
@Observable
public final class Spin: PerchPlugin {
    public static let identifier = "org.ahlab.perch.spin"
    public static let displayName = "Spin"
    public static let icon = "record.circle"
    public static let capabilities: Set<PluginCapability> = [.network, .media]

    public let model: SpinModel

    @ObservationIgnored private let source = NowPlayingSource()
    @ObservationIgnored private var desktop: DesktopSceneController?
    @ObservationIgnored private var sleepTokens: [NSObjectProtocol] = []

    public convenience init(context: PluginContext) {
        let runner = NSAppleScriptRunner()
        self.init(
            context: context,
            scenes: SceneCatalog.builtIn,
            artwork: ArtworkFetcher(runner: runner, cacheDirectory: context.storage.url(named: "Artwork")),
            query: ScriptedPlayerQuery(runner: runner)
        )
    }

    /// The testable initializer.
    init(context: PluginContext, scenes: [SceneAsset], artwork: ArtworkProviding, query: PlayerQuerying) {
        model = SpinModel(defaults: context.defaults, scenes: scenes, artworkProvider: artwork, query: query)
    }

    public var panel: AnyView { AnyView(SpinPanelView(model: model)) }

    public var menuBarLabel: MenuBarLabel? {
        guard let event = model.nowPlaying, event.state == .playing, let track = event.track else {
            return MenuBarLabel(systemImage: Self.icon)
        }
        let text = track.artist.isEmpty ? track.title : "\(track.title) – \(track.artist)"
        return MenuBarLabel(systemImage: Self.icon, text: text)
    }

    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            source.onEvent = { [weak model] in model?.receive($0) }
            source.onPing = { [weak model] in model?.refresh($0) }
            source.start()
            model.activate()
            let desktop = DesktopSceneController(model: model)
            desktop.start()
            self.desktop = desktop
            observeSleep()
        } else {
            source.stop()
            desktop?.stop()
            desktop = nil
            for token in sleepTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            sleepTokens = []
            model.reset()
        }
    }

    /// No one is watching a locked or sleeping screen; stop drawing.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        sleepTokens = pairs.map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.isScreenAsleep = asleep }
            }
        }
    }
}
```

- [ ] **Step 7: Run plugin tests**

Run: `swift test --package-path Plugins/SpinPlugin 2>&1 | grep -E "Executed|error:|failed"`
Expected: 0 failures. Fix any SwiftUI compile errors (e.g. `.position(frames.sleeveCenter)` needs `CGPoint` overload — it exists).

- [ ] **Step 8: Wire into the host**

`project.yml`: under `packages:` add

```yaml
  SpinPlugin:
    path: Plugins/SpinPlugin
```

and in both the `Perch` and `PerchTests` `dependencies:` lists, after `TapPlugin`:

```yaml
      - package: SpinPlugin
        product: SpinPlugin
```

In the `Perch` target `info.properties`, add:

```yaml
        NSAppleEventsUsageDescription: "Spin reads the current track and its album art from Spotify and Music to draw them on your desktop."
```

`Perch/Perch.entitlements`: add before `</dict>`:

```xml
	<key>com.apple.security.temporary-exception.apple-events</key>
	<array>
		<string>com.spotify.client</string>
		<string>com.apple.Music</string>
	</array>
```

`Perch/PerchApp.swift`: add `import SpinPlugin` in alphabetical position (after `import ServerPlugin`), and append `Spin(context: .perch(Spin.identifier)),` after the `Tap(...)` line in `makePlugins()`.

- [ ] **Step 9: Build and run the host tests**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | grep -E "Executed|error:|FAILED" | tail -5
```

Expected: `** TEST SUCCEEDED **`, including the updated `PluginCapabilityTests`. Confirm `grep NSAppleEventsUsageDescription Perch/Info.plist` finds the key.

- [ ] **Step 10: Commit**

```bash
git add Plugins/SpinPlugin project.yml Perch.xcodeproj Perch/Perch.entitlements Perch/Info.plist Perch/PerchApp.swift
git commit -m "feat(spin): desktop scene, panel, and host wiring"
```

---

### Task 9: Verify on the real Mac, then document

**Files:**
- Modify: `README.md` (intro list and a new `### Spin` section after `### Tap`)
- Modify: `docs/superpowers/specs/2026-10-04-spin-plugin-design.md` (status and the two deviations)

- [ ] **Step 1: Build and launch Debug**

```bash
xcodebuild build -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build 2>&1 | tail -2
pkill -x Perch; open build/Build/Products/Debug/Perch.app
```

- [ ] **Step 2: Walk the checklist, screenshotting with `screencapture -x /tmp/spin-N.png` and viewing each with the Read tool**

1. Spin tab present; toggle off; play Spotify (`osascript -e 'tell application "Spotify" to play'`) → panel shows the track, menu bar shows `Title – Artist`, **no** scene and **no** Automation prompt.
2. Turn the toggle on → Automation prompt for Spotify; allow → scene fades in within ~1 s, label and sleeve show the album art, record spins, tonearm (if drawn) on the record. Desktop icons stay above the scene; windows stay above it; clicks on the desktop still reach Finder.
3. Sandbox payload check: if the panel shows the track, distributed userInfo arrived. If it updates only after a delay, the ping fallback is doing the work — note which in the spec.
4. `osascript -e 'tell application "Spotify" to next track'` twice quickly → art matches the final track.
5. Pause → record eases to a stop, scene stays; after 2 minutes it fades out.
6. Switch scene in the panel → background changes in place.
7. Quit Spotify while playing → scene fades after 2 minutes, Spotify is not relaunched.
8. Repeat 2 with Music, if it has a playable track.
9. In System Settings › Privacy › Automation, revoke Perch → Spotify, skip a track → fallback label, panel shows "Open Settings".
10. Disable Spin in Settings mid-playback → scene gone immediately.
11. Change display arrangement or resolution while visible → scene refits.

Fix anything that fails before continuing, with a test where the logic allows.

- [ ] **Step 3: Write the README section**

Add "**Spin**, which turns your desktop into a turntable playing whatever's on" to the intro list, and after `### Tap`:

```markdown
### Spin

While Spotify or Apple Music plays, your desktop becomes a room with a
turntable: the album art is the record's label and the sleeve beside it, the
record turns while the music does and eases to a stop when you pause.

- **Off until you turn it on.** Switch on "Show scene on desktop" in the Spin
  tab. macOS asks once per player whether Perch may read it.
- **Two rooms.** *Listening Room* in daylight and *After Hours* by lamplight.
- **Your wallpaper is untouched.** The scene is a window behind your icons;
  two minutes after the music stops it fades and your desktop is back.

Spin declares `network` (to download Spotify's album art) and `media`: it
sends Apple Events to Spotify and Music, and only while they are running.
```

- [ ] **Step 4: Update the spec**

Set **Status** to `implemented`. Under "What the user sees", add: "The scene is off until the user turns it on in the panel (decided while planning: upgraders get new plugins enabled)." In the descriptor section, replace the JSON example with the shipped `listening-room/scene.json` and note that `tonearm` is optional. Record the step 2.3 finding on sandboxed userInfo.

- [ ] **Step 5: Final checks and commit**

```bash
swift test --package-path Plugins/SpinPlugin 2>&1 | grep Executed
git add README.md docs/superpowers/specs/2026-10-04-spin-plugin-design.md
git commit -m "docs: Spin plugin"
```

Expected: all tests pass.
