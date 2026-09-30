import Foundation

/// What to fetch and where to put it.
public struct DownloadRequest: Equatable, Sendable {
    public var url: URL
    public var format: MediaFormat
    public var maxHeight: Int?
    public var destination: URL

    public init(url: URL, format: MediaFormat, maxHeight: Int?, destination: URL) {
        self.url = url
        self.format = format
        self.maxHeight = maxHeight
        self.destination = destination
    }
}

public struct DownloaderError: Error, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

/// Looks links up and saves them. The seam the store is tested through.
public protocol Downloader: Sendable {
    /// Whether the tools this needs are installed. Asked again when the user
    /// says they have just installed them.
    func isAvailable() -> Bool
    func info(for url: URL) async throws -> MediaInfo
    /// Returns the saved file. Cancelling the calling task stops the download.
    func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL
}
