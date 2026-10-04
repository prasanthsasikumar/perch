# Spin plugin — design

**Date:** 2026-10-04
**Status:** approved in conversation, spec awaiting review

While Spotify or Apple Music plays, the desktop becomes a room with a
turntable: the album art is the record's centre label and a sleeve in the
scene, the record spins while music plays and slows to a stop on pause. When
the music has been stopped for a while the scene fades and the user's own
wallpaper is back.

The name is deliberately not "Vinyl": the screenshots that inspired this are
from a commercial app called *Vinyl for Mac*. Nothing of theirs — name,
photos, layout — ships here.

## What the user sees

- Playback starts in Spotify or Music → a full-screen scene fades in on the
  **main display**, below desktop icons and every window.
- The record's label is the current album art, clipped to a circle; the same
  art appears as a sleeve (where the scene places it). The record spins at
  33⅓ rpm; the tonearm rests on it while playing and swings off when stopped.
- Pause → the record eases to a stop over ~1.5 s; the scene stays.
- Stopped, or player quit → after **2 minutes** of no playback the scene
  fades out. Resuming inside that window brings the spin straight back.
- Track change → the label and sleeve cross-fade to the new art.
- Two built-in scenes: **Listening Room** (daylight, wood desk) and **After
  Hours** (warm lamp light). Chosen in the panel.

Out of scope for v1, by decision: user-supplied scenes (and the editor to
place the turntable on them), other displays, playback controls, players
other than Spotify and Music (browser audio would need MediaRemote, which
macOS 15.4 locked to entitled Apple processes).

## Panel and menu bar

- **Panel tab "Spin"** (SF Symbol `record.circle`): the current track (art,
  title, artist, player), a scene picker of thumbnails, and a "Show scene on
  desktop" toggle. If Apple Events permission was denied, a line saying so
  with a button that opens System Settings › Privacy › Automation.
- **Menu bar** while the tab is selected: `record.circle` plus
  `Title – Artist` while something plays; icon only otherwise.

## Where the data comes from

**Track and state — distributed notifications.** No permission needed;
receiving is allowed from the sandbox.

| Player  | Notification                          | Keys used                                               |
|---------|---------------------------------------|---------------------------------------------------------|
| Spotify | `com.spotify.client.PlaybackStateChanged` | `Player State`, `Name`, `Artist`, `Album`, `Track ID` |
| Music   | `com.apple.Music.playerInfo`          | `Player State`, `Name`, `Artist`, `Album`, `PersistentID` |

`Player State` is `Playing` / `Paused` / `Stopped`. Both players are also
asked once at plugin start (only if already running, via
`NSRunningApplication`) so a scene can appear without waiting for the next
track change. Implementation must verify against the real apps on this Mac
that userInfo arrives intact in the sandboxed Perch; if it does not, the
fallback is to treat the notification as a ping and read state over
AppleScript.

**Album art — Apple Events.** Fetched once per track, cached on disk by
track ID (last 50 kept):

- Spotify: `tell application "Spotify" to artwork url of current track` →
  an `https://i.scdn.co/...` URL → downloaded (hence `network`).
- Music: `tell application "Music" to data of artwork 1 of current track` →
  raw image bytes.

This needs `com.apple.security.temporary-exception.apple-events` for exactly
`com.spotify.client` and `com.apple.Music`, plus `NSAppleEventsUsageDescription`
in Info.plist. macOS asks the user once per player. Scripts are only sent to
a player that is already running (an Apple Event to a quit app launches it).

## Components

```
Plugins/SpinPlugin/Sources/SpinPlugin/
  Spin.swift                    the PerchPlugin; wires source → store → window
  NowPlaying/
    NowPlaying.swift            Track (id, title, artist, album, player) + PlaybackState
    PlayerNotification.swift    pure: notification name + userInfo → NowPlaying?
    NowPlayingSource.swift      observes both players; latest-started wins
    ArtworkFetcher.swift        Apple Events + download + on-disk cache
    AppleScriptRunner.swift     the seam; NSAppleScript behind a protocol for tests
  Scene/
    SceneDescriptor.swift       Codable placement data for one scene
    SceneCatalog.swift          the built-in scenes, loaded from Resources/
    SceneLayout.swift           pure: descriptor + screen size → frames (aspect-fill aware)
    SceneVisibility.swift       pure: state timeline → visible / spinning / fading
    Resources/scenes/<id>/{background.jpg, scene.json, thumb.jpg}
  Desktop/
    DesktopSceneWindow.swift    borderless NSWindow at desktop level, click-through
  Views/
    SceneView.swift             background + record + tonearm + sleeve
    RecordView.swift            grooved disc, circular label, spin animation
    SpinPanelView.swift         the panel tab
```

**SceneDescriptor** (all positions are fractions of the background image, so
one file serves every screen size):

```json
{
  "id": "listening-room",
  "name": "Listening Room",
  "platter": { "x": 0.43, "y": 0.66, "radius": 0.11, "squash": 0.42 },
  "tonearm": { "pivotX": 0.53, "pivotY": 0.55, "restAngle": -25, "playAngle": 8 },
  "sleeve": { "x": 0.18, "y": 0.42, "width": 0.18, "height": 0.26, "rotation": -2, "style": "stand" }
}
```

`squash` is the vertical scale of the record ellipse, because the photos
look down at the desk at an angle. `style` is `stand` (upright in a holder)
or `flat` (lying on the desk, drawn with a slight perspective transform).

**Background photos** are generated with Gemini's image model as empty rooms:
desk, turntable with an empty platter, an empty picture stand or clear desk
space for the sleeve, no text or logos. The plugin draws the record, label,
tonearm and sleeve, so the photos never contain album art. Placement numbers
are tuned by eye per photo. Photos ship as ~2880 px JPEGs; they are meant to
be swapped later, and swapping one means replacing the JPEG and retuning its
`scene.json`.

**DesktopSceneWindow**: `level = CGWindowLevelForKey(.desktopWindow)`,
`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`,
`ignoresMouseEvents = true`, sized to `NSScreen.main`'s full frame and
re-sized on `didChangeScreenParametersNotification`. It exists only while
the plugin is enabled *and* the toggle is on *and* `SceneVisibility` says
visible; otherwise it is closed, not hidden. It is kept out of Mission
Control the same way parked webviews are (see `ParkedWindow`).

## Lifecycle

- `init` does nothing active (the PerchPlugin contract).
- `setEnabled(true)` starts observing notifications and does the one-shot
  state read; `setEnabled(false)` removes observers, cancels fetches,
  closes the window.
- The spin animation runs only while the window is on screen, and stops
  while the screen is locked or asleep (`NSWorkspace` session/sleep
  notifications) to avoid burning GPU for no one.

## Capabilities

- `network` — downloads Spotify's artwork.
- New `PluginCapability.media`: "Reads what's playing in Spotify and Music".

## Errors and edge cases

- No art, or Apple Events denied → label drawn in a neutral scene colour
  with the track title; the panel explains the permission.
- Both players playing → whichever most recently sent `Playing` wins.
- Spotify ads / podcasts without art → same as no art.
- Display change while visible → window re-fits; nothing restarts.

## Testing

- Unit: `PlayerNotification` parsing with captured real userInfo
  dictionaries for both players and all three states; `SceneVisibility`
  timing (play, pause, stop → 2 min fade, resume within window);
  `SceneLayout` frames for 16:10, 16:9 and ultrawide screens against a 3:2
  background; `ArtworkFetcher` cache and the "don't script a quit player"
  rule via a fake `AppleScriptRunner`.
- Manual, on this Mac: real Spotify and Music playback through
  play/pause/skip/quit, each scene screenshotted, permission-denied path,
  and the plugin disabled mid-playback.
