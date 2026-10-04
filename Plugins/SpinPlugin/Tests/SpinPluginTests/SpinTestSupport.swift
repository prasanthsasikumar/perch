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
