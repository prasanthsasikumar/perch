import AppKit
import Foundation
import Observation
import PerchKit

/// What the plugin keeps on disk: the files it has saved, so the panel can
/// offer them again after a relaunch.
public struct DownloadDocument: Codable, Equatable, Sendable {
    public var recent: [FinishedDownload]

    public init(recent: [FinishedDownload] = []) {
        self.recent = recent
    }
}

/// Pasted links, their lookups and downloads, and the recent files list.
///
/// Links in flight live in memory only. A download interrupted by quitting is
/// not resumed — yt-dlp's partial files are in a temporary directory that is
/// already gone.
@MainActor
@Observable
public final class DownloadStore {
    public static let recentCapacity = 20

    public var format: MediaFormat {
        didSet { defaults.set(format.rawValue, for: "format") }
    }
    public private(set) var jobs: [DownloadJob] = []
    public private(set) var recent: [FinishedDownload] = []
    public private(set) var isAvailable: Bool
    public private(set) var saveFailureNotice: String?
    public private(set) var loadFailureNotice: String?

    public let destination: URL

    private let storage: PluginStorage
    private let defaults: PluginDefaults
    private let downloader: Downloader
    private let clock: () -> Date
    private let filename: String
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(
        storage: PluginStorage,
        defaults: PluginDefaults,
        downloader: Downloader,
        destination: URL = DownloadStore.userDownloads,
        clock: @escaping () -> Date = { .now },
        filename: String = "downloads.json"
    ) {
        self.storage = storage
        self.defaults = defaults
        self.downloader = downloader
        self.destination = destination
        self.clock = clock
        self.filename = filename
        format = defaults.string("format").flatMap(MediaFormat.init(rawValue:)) ?? .video
        isAvailable = downloader.isAvailable()
        load()
    }

    /// The real `~/Downloads`. Inside the sandbox `FileManager` answers with
    /// the container's own Downloads; that is a symlink to this one, but the
    /// path it gives is not the one the user knows.
    public nonisolated static var userDownloads: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Derived

    public var activeDownloads: [DownloadJob] { jobs.filter(\.isDownloading) }

    public var readyCount: Int { jobs.filter { $0.state == .ready }.count }

    // MARK: - Tools

    public func recheckTools() {
        isAvailable = downloader.isAvailable()
    }

    // MARK: - Adding

    /// Adds every link in `text` that isn't already in the list and starts
    /// looking each one up. Returns how many were added, so the field can
    /// keep text that held no links rather than swallowing it.
    @discardableResult
    public func add(_ text: String) -> Int {
        let existing = Set(jobs.map(\.url.absoluteString))
        let urls = PastedLinks.extract(text).filter { !existing.contains($0.absoluteString) }
        for url in urls {
            let job = DownloadJob(url: url)
            jobs.append(job)
            fetch(job.id)
        }
        return urls.count
    }

    private func fetch(_ id: UUID) {
        guard let url = job(id)?.url else { return }
        update(id) { $0.state = .fetching }
        let downloader = downloader
        tasks[id] = Task { [weak self] in
            do {
                let info = try await downloader.info(for: url)
                guard !Task.isCancelled else { return }
                self?.update(id) {
                    $0.info = info
                    $0.state = .ready
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.update(id) { $0.state = .failed(Self.describe(error)) }
            }
            self?.tasks[id] = nil
        }
    }

    // MARK: - Downloading

    public func setMaxHeight(_ height: Int?, for id: UUID) {
        update(id) { $0.maxHeight = height }
    }

    public func download(_ id: UUID) {
        guard let job = job(id), tasks[id] == nil else { return }
        let request = DownloadRequest(
            url: job.url,
            format: format,
            maxHeight: format == .video ? job.maxHeight : nil,
            destination: destination
        )
        update(id) { $0.state = .downloading(progress: nil) }
        let downloader = downloader
        tasks[id] = Task { [weak self] in
            do {
                let file = try await downloader.download(request) { fraction in
                    Task { @MainActor in
                        self?.update(id) { job in
                            guard job.isDownloading else { return }
                            job.state = .downloading(progress: fraction)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                self?.finish(id, file: file)
            } catch {
                guard !Task.isCancelled else { return }
                self?.update(id) { $0.state = .failed(Self.describe(error)) }
            }
            self?.tasks[id] = nil
        }
    }

    public func downloadAll() {
        for job in jobs where job.state == .ready { download(job.id) }
    }

    /// A failed lookup is looked up again; a failed download is downloaded
    /// again.
    public func retry(_ id: UUID) {
        guard let job = job(id), case .failed = job.state else { return }
        if job.info == nil { fetch(id) } else { download(id) }
    }

    /// Stops a download and puts the link back to ready.
    public func cancel(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        update(id) { $0.state = $0.info == nil ? .failed("Cancelled.") : .ready }
    }

    public func cancelAll() {
        for id in tasks.keys { cancel(id) }
    }

    public func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        jobs.removeAll { $0.id == id }
    }

    private func finish(_ id: UUID, file: URL) {
        guard let job = job(id) else { return }
        jobs.removeAll { $0.id == id }
        recent.insert(FinishedDownload(title: job.title, file: file, source: job.url, at: clock()), at: 0)
        if recent.count > Self.recentCapacity { recent.removeLast(recent.count - Self.recentCapacity) }
        saveNow()
    }

    // MARK: - Recent

    public func reveal(_ item: FinishedDownload) {
        NSWorkspace.shared.activateFileViewerSelecting([item.file])
    }

    public func open(_ item: FinishedDownload) {
        NSWorkspace.shared.open(item.file)
    }

    public func openDestination() {
        NSWorkspace.shared.open(destination)
    }

    public func clearRecent() {
        recent.removeAll()
        saveNow()
    }

    // MARK: - Helpers

    private func job(_ id: UUID) -> DownloadJob? {
        jobs.first { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private static func describe(_ error: Error) -> String {
        (error as? DownloaderError)?.message ?? error.localizedDescription
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(DownloadDocument.self, named: filename) else { return }
            // Files the user has since moved or deleted would only offer a
            // Finder window with nothing selected.
            recent = document.recent.filter { FileManager.default.fileExists(atPath: $0.file.path) }
        } catch {
            loadFailureNotice = "Couldn't read the recent downloads. A copy was kept as \(filename).bak."
        }
    }

    public func saveNow() {
        do {
            try storage.save(DownloadDocument(recent: recent), named: filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save the recent downloads."
        }
    }
}
