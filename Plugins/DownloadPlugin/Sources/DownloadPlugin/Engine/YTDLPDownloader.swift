import Foundation

/// The real `Downloader`: runs the user's Homebrew yt-dlp.
///
/// Not bundled, on purpose. Sites change under yt-dlp every few weeks and it
/// ships fixes just as often; a copy frozen into Perch would go stale between
/// releases, while `brew upgrade` keeps this one current.
public struct YTDLPDownloader: Downloader {
    /// How long a lookup may take before it is given up on. Downloads have no
    /// limit — a long video on a slow line is not a hang.
    public static let infoTimeout: Duration = .seconds(60)

    public init() {}

    public func isAvailable() -> Bool { YTDLP.locate() != nil }

    public func info(for url: URL) async throws -> MediaInfo {
        let tools = try requireTools()
        let result = try await withThrowingTaskGroup(of: ProcessRunner.Result?.self) { group in
            group.addTask {
                try await ProcessRunner.run(
                    tools.ytdlp, arguments: YTDLP.infoArguments(for: url), environment: environment(tools)
                )
            }
            group.addTask {
                try await Task.sleep(for: Self.infoTimeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let result else { throw DownloaderError("Timed out looking up the link.") }
        guard result.status == 0 else {
            throw DownloaderError(YTDLP.errorMessage(fromStderr: result.stderr))
        }
        do {
            return try MediaInfo.parse(Data(result.stdout.utf8))
        } catch {
            throw DownloaderError("yt-dlp's answer couldn't be read.")
        }
    }

    public func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let tools = try requireTools()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        // Whatever yt-dlp leaves behind — `.part` files from a cancelled
        // download, streams it never merged — goes with the directory.
        defer { try? FileManager.default.removeItem(at: temporary) }

        let throttle = ProgressThrottle(forward: progress)
        let result = try await ProcessRunner.run(
            tools.ytdlp,
            arguments: YTDLP.downloadArguments(for: request, ffmpeg: tools.ffmpeg, temporary: temporary),
            environment: environment(tools)
        ) { line in
            if case .progress(let fraction) = YTDLP.parse(line: line) { throttle.report(fraction) }
        }
        try Task.checkCancellation()
        guard result.status == 0 else {
            throw DownloaderError(YTDLP.errorMessage(fromStderr: result.stderr))
        }
        guard let path = YTDLP.filePath(fromStdout: result.stdout) else {
            throw DownloaderError("Download finished but the file wasn't reported.")
        }
        return URL(fileURLWithPath: path)
    }

    private func requireTools() throws -> YTDLP.Tools {
        guard let tools = YTDLP.locate() else {
            throw DownloaderError("yt-dlp and ffmpeg aren't installed.")
        }
        return tools
    }

    /// A UTF-8 locale so titles with accents or emoji survive into filenames,
    /// and a PATH that finds ffmpeg's neighbours.
    private func environment(_ tools: YTDLP.Tools) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let bin = tools.ytdlp.deletingLastPathComponent().path
        environment["PATH"] = "\(bin):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["PYTHONIOENCODING"] = "utf-8"
        return environment
    }
}

/// yt-dlp reports progress many times a second. Only whole-percent changes
/// are passed on, so the panel isn't redrawn for every chunk.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Int?? = .none
    private let forward: @Sendable (Double?) -> Void

    init(forward: @escaping @Sendable (Double?) -> Void) { self.forward = forward }

    func report(_ fraction: Double?) {
        let percent = fraction.map { Int($0 * 100) }
        let changed: Bool = lock.withLock {
            if case .some(let previous) = last, previous == percent { return false }
            last = .some(percent)
            return true
        }
        if changed { forward(fraction) }
    }
}
