import Foundation

/// One pasted link, from looking it up to the file landing in Downloads.
public struct DownloadJob: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case fetching
        case ready
        /// `nil` progress until yt-dlp reports a size, and again once the
        /// bytes are in and ffmpeg is merging or converting.
        case downloading(progress: Double?)
        case failed(String)
    }

    public let id: UUID
    public let url: URL
    public var info: MediaInfo?
    /// The tallest video to accept; `nil` for the best available.
    public var maxHeight: Int?
    public var state: State

    public init(id: UUID = UUID(), url: URL, info: MediaInfo? = nil, maxHeight: Int? = nil, state: State = .fetching) {
        self.id = id
        self.url = url
        self.info = info
        self.maxHeight = maxHeight
        self.state = state
    }

    public var title: String { info?.title ?? url.absoluteString }

    public var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }
}

/// A file Perch saved, kept so the panel can offer it again.
public struct FinishedDownload: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let file: URL
    public let source: URL
    public let at: Date

    public init(id: UUID = UUID(), title: String, file: URL, source: URL, at: Date) {
        self.id = id
        self.title = title
        self.file = file
        self.source = source
        self.at = at
    }
}
