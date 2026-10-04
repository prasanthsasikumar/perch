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
