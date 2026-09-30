@testable import DownloadPlugin
import PerchKit
import XCTest

/// Answers lookups and downloads with whatever was queued, and holds a
/// download open until told to finish, so in-flight state can be seen.
final class FakeDownloader: Downloader, @unchecked Sendable {
    private let lock = NSLock()
    var available = true
    var infoResult: Result<MediaInfo, Error> = .success(MediaInfo(title: "Clip", heights: [1080, 720]))
    var downloadResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/Clip.mp4"))
    var holdDownloads = false
    private(set) var requests: [DownloadRequest] = []
    private var gates: [CheckedContinuation<Void, Never>] = []

    func isAvailable() -> Bool { available }

    func info(for url: URL) async throws -> MediaInfo { try infoResult.get() }

    func download(_ request: DownloadRequest, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        lock.withLock { requests.append(request) }
        progress(0.5)
        if holdDownloads {
            await withCheckedContinuation { continuation in
                lock.withLock { gates.append(continuation) }
            }
        }
        try Task.checkCancellation()
        return try downloadResult.get()
    }

    func release() {
        let pending = lock.withLock { defer { gates.removeAll() }; return gates }
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class DownloadStoreTests: XCTestCase {
    private var directory: URL!
    private var suite: UserDefaults!
    private let destination = URL(fileURLWithPath: "/Users/me/Downloads")

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = UserDefaults(suiteName: "DownloadStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(_ downloader: FakeDownloader) -> DownloadStore {
        DownloadStore(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(suite: suite, prefix: "test"),
            downloader: downloader,
            destination: destination
        )
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testAddingLooksEachNewLinkUp() async {
        let store = makeStore(FakeDownloader())
        XCTAssertEqual(store.add("https://youtu.be/a https://youtu.be/b"), 2)
        XCTAssertEqual(store.add("https://youtu.be/a"), 0, "already in the list")
        await settle { store.readyCount == 2 }
        XCTAssertEqual(store.jobs.map(\.title), ["Clip", "Clip"])
    }

    func testFailedLookupShowsTheMessageAndRetriesTheLookup() async {
        let downloader = FakeDownloader()
        downloader.infoResult = .failure(DownloaderError("Unsupported URL"))
        let store = makeStore(downloader)
        store.add("https://example.com/page")
        await settle { store.jobs.first?.state != .fetching }
        XCTAssertEqual(store.jobs.first?.state, .failed("Unsupported URL"))

        downloader.infoResult = .success(MediaInfo(title: "Now it works"))
        store.retry(store.jobs[0].id)
        await settle { store.readyCount == 1 }
        XCTAssertEqual(store.jobs.first?.title, "Now it works")
    }

    func testDownloadPassesFormatAndHeightThenMovesToRecent() async {
        let downloader = FakeDownloader()
        let store = makeStore(downloader)
        store.add("https://youtu.be/a")
        await settle { store.readyCount == 1 }
        store.setMaxHeight(720, for: store.jobs[0].id)
        store.download(store.jobs[0].id)
        await settle { store.jobs.isEmpty }

        XCTAssertEqual(downloader.requests, [
            DownloadRequest(url: URL(string: "https://youtu.be/a")!, format: .video, maxHeight: 720, destination: destination)
        ])
        XCTAssertEqual(store.recent.map(\.title), ["Clip"])
        XCTAssertEqual(store.recent.first?.file.path, "/tmp/Clip.mp4")
    }

    func testAudioIgnoresTheChosenHeight() async {
        let downloader = FakeDownloader()
        let store = makeStore(downloader)
        store.format = .audio
        store.add("https://youtu.be/a")
        await settle { store.readyCount == 1 }
        store.setMaxHeight(720, for: store.jobs[0].id)
        store.download(store.jobs[0].id)
        await settle { store.jobs.isEmpty }
        XCTAssertEqual(downloader.requests.first?.format, .audio)
        XCTAssertNil(downloader.requests.first?.maxHeight)
    }

    func testCancelPutsTheLinkBackToReady() async {
        let downloader = FakeDownloader()
        downloader.holdDownloads = true
        let store = makeStore(downloader)
        store.add("https://youtu.be/a")
        await settle { store.readyCount == 1 }
        let id = store.jobs[0].id
        store.download(id)
        await settle { store.jobs.first?.state == .downloading(progress: 0.5) }
        XCTAssertEqual(store.activeDownloads.count, 1)

        store.cancel(id)
        downloader.release()
        await settle { false }
        XCTAssertEqual(store.jobs.first?.state, .ready)
        XCTAssertTrue(store.recent.isEmpty)
    }

    func testFormatAndRecentSurviveARelaunch() async {
        let file = directory.appendingPathComponent("Clip.mp4")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let downloader = FakeDownloader()
        downloader.downloadResult = .success(file)
        let store = makeStore(downloader)
        store.format = .audio
        store.add("https://youtu.be/a")
        await settle { store.readyCount == 1 }
        store.download(store.jobs[0].id)
        await settle { !store.recent.isEmpty }

        let reopened = makeStore(FakeDownloader())
        XCTAssertEqual(reopened.format, .audio)
        XCTAssertEqual(reopened.recent.map(\.file), [file])
    }

    func testRecentDropsFilesThatNoLongerExist() async {
        let store = makeStore(FakeDownloader())  // downloads report /tmp/Clip.mp4, which isn't there
        store.add("https://youtu.be/a")
        await settle { store.readyCount == 1 }
        store.download(store.jobs[0].id)
        await settle { !store.recent.isEmpty }
        XCTAssertTrue(makeStore(FakeDownloader()).recent.isEmpty)
    }

    func testMenuBarShowsProgressWhileDownloading() async {
        let downloader = FakeDownloader()
        downloader.holdDownloads = true
        let plugin = Download(
            context: PluginContext(storage: PluginStorage(directory: directory),
                                   defaults: PluginDefaults(suite: suite, prefix: "test")),
            downloader: downloader,
            destination: destination
        )
        XCTAssertEqual(plugin.menuBarLabel, MenuBarLabel(systemImage: "arrow.down.circle"))
        plugin.store.add("https://youtu.be/a")
        await settle { plugin.store.readyCount == 1 }
        plugin.store.download(plugin.store.jobs[0].id)
        await settle { plugin.store.jobs.first?.state == .downloading(progress: 0.5) }
        XCTAssertEqual(plugin.menuBarLabel, MenuBarLabel(systemImage: "arrow.down.circle.fill", text: "50%"))

        plugin.setEnabled(false)
        XCTAssertTrue(plugin.store.activeDownloads.isEmpty, "switching off stops downloads")
        downloader.release()
    }

    func testMissingToolsAreReportedAndRechecked() {
        let downloader = FakeDownloader()
        downloader.available = false
        let store = makeStore(downloader)
        XCTAssertFalse(store.isAvailable)
        downloader.available = true
        store.recheckTools()
        XCTAssertTrue(store.isAvailable)
    }
}
