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
        isRunning: @escaping @Sendable (Player) -> Bool = { PlayerProcess.isRunning($0) },
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
