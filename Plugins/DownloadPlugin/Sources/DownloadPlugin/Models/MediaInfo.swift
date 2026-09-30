import Foundation

/// The parts of yt-dlp's `-j` output the panel shows.
public struct MediaInfo: Equatable, Sendable {
    public var title: String
    public var thumbnail: URL?
    public var duration: TimeInterval?
    public var uploader: String?
    /// Video heights on offer, tallest first, one per height. Empty for
    /// audio-only sources.
    public var heights: [Int]

    public init(
        title: String,
        thumbnail: URL? = nil,
        duration: TimeInterval? = nil,
        uploader: String? = nil,
        heights: [Int] = []
    ) {
        self.title = title
        self.thumbnail = thumbnail
        self.duration = duration
        self.uploader = uploader
        self.heights = heights
    }
}

public enum MediaInfoError: Error, Equatable {
    case empty
}

extension MediaInfo {
    private struct Raw: Decodable {
        struct Format: Decodable {
            let height: Int?
            let vcodec: String?
        }

        let title: String?
        let thumbnail: String?
        let duration: Double?
        let uploader: String?
        let formats: [Format]?
    }

    /// Reads the first JSON object in yt-dlp's `-j` output.
    ///
    /// The first, not the only: `-j` prints one object per line, and some
    /// extractors emit several even with `--no-playlist`.
    public static func parse(_ output: Data) throws -> MediaInfo {
        let lines = output.split(separator: UInt8(ascii: "\n"))
        guard let line = lines.first(where: { !$0.allSatisfy { $0 == UInt8(ascii: " ") } }) else {
            throw MediaInfoError.empty
        }
        let raw = try JSONDecoder().decode(Raw.self, from: Data(line))
        let heights = Set((raw.formats ?? []).compactMap { format -> Int? in
            guard let height = format.height, height > 0, format.vcodec != "none" else { return nil }
            return height
        })
        return MediaInfo(
            title: raw.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
            thumbnail: raw.thumbnail.flatMap(URL.init(string:)),
            duration: raw.duration,
            uploader: raw.uploader.flatMap { $0.isEmpty ? nil : $0 },
            heights: heights.sorted(by: >)
        )
    }
}
