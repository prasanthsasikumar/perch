import Foundation

/// Everything about talking to yt-dlp that doesn't need a process: where it
/// lives, what to pass it, and how to read what it prints back.
public enum YTDLP {
    /// Homebrew's two prefixes. Perch is sandboxed and its entitlements grant
    /// read access to exactly these, so a yt-dlp installed anywhere else could
    /// not be run even if it were found.
    public static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    public struct Tools: Equatable, Sendable {
        public let ytdlp: URL
        public let ffmpeg: URL
    }

    /// Both tools, from the first directory that has each. ffmpeg is required
    /// rather than optional: without it yt-dlp can neither merge the separate
    /// video and audio streams most sites serve nor make an MP3.
    public static func locate(
        in directories: [String] = searchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Tools? {
        func find(_ name: String) -> URL? {
            directories
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
                .first { isExecutable($0.path) }
        }
        guard let ytdlp = find("yt-dlp"), let ffmpeg = find("ffmpeg") else { return nil }
        return Tools(ytdlp: ytdlp, ffmpeg: ffmpeg)
    }

    static let progressMarker = "PERCH-PROGRESS"

    /// `--ignore-config` everywhere: a user's own yt-dlp config could change
    /// the output this parses, or the filename it reports.
    public static func infoArguments(for url: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-warnings", "-j", url.absoluteString]
    }

    public static func downloadArguments(
        for request: DownloadRequest,
        ffmpeg: URL,
        temporary: URL
    ) -> [String] {
        var arguments = [
            "--ignore-config", "--no-playlist", "--no-warnings",
            "--newline", "--progress",
            "--progress-template",
            "download:\(progressMarker) %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            // The final path, printed once the file is in place — which is how
            // the panel knows what to reveal in Finder.
            "--print", "after_move:filepath",
            // Stamped with today, not the upload date, so it sorts to the top
            // of Downloads where the user will look for it.
            "--no-mtime",
            "--ffmpeg-location", ffmpeg.path,
            "-P", request.destination.path,
            // Partial and intermediate files stay out of Downloads until done.
            "-P", "temp:\(temporary.path)",
            "-o", "%(title).150B.%(ext)s",
        ]
        switch request.format {
        case .audio:
            arguments += ["-x", "--audio-format", "mp3"]
        case .video:
            let selector = request.maxHeight.map { "bv*[height<=\($0)]+ba/b[height<=\($0)]/b" } ?? "bv*+ba/b"
            arguments += ["-f", selector, "--merge-output-format", "mp4"]
        }
        arguments.append(request.url.absoluteString)
        return arguments
    }

    public enum Line: Equatable {
        /// A progress update. `nil` fraction when yt-dlp doesn't know the size.
        case progress(Double?)
        case other(String)
    }

    public static func parse(line: String) -> Line {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(progressMarker) else { return .other(trimmed) }
        let fields = trimmed.split(separator: " ").dropFirst().map { Double($0) }
        guard let done = fields.first ?? nil else { return .progress(nil) }
        let total = fields.dropFirst().compactMap { $0 }.first { $0 > 0 }
        guard let total else { return .progress(nil) }
        return .progress(min(max(done / total, 0), 1))
    }

    /// The saved file's path: the last line of stdout that isn't progress.
    public static func filePath(fromStdout stdout: String) -> String? {
        stdout.split(whereSeparator: \.isNewline).reversed().lazy
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix(progressMarker) }
    }

    /// yt-dlp's own explanation, trimmed for a one-line caption: the last
    /// `ERROR:` line, minus the prefix and the extractor tag.
    public static func errorMessage(fromStderr stderr: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map(String.init)
        guard var message = lines.last(where: { $0.hasPrefix("ERROR:") }) ?? lines.last else {
            return "yt-dlp stopped without saying why."
        }
        if message.hasPrefix("ERROR:") { message.removeFirst("ERROR:".count) }
        message = message.trimmingCharacters(in: .whitespaces)
        // "[youtube] abc123: Video unavailable" → "Video unavailable"
        if message.hasPrefix("["), let close = message.firstIndex(of: "]") {
            let rest = message[message.index(after: close)...]
            if let colon = rest.firstIndex(of: ":") {
                message = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return message.isEmpty ? "yt-dlp stopped without saying why." : message
    }
}
