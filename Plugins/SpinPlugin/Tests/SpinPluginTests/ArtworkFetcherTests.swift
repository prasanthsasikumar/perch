@testable import SpinPlugin
import XCTest

final class ArtworkFetcherTests: XCTestCase {
    private var cache: URL!
    private let runner = FakeScriptRunner()

    override func setUp() {
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache)
    }

    private func fetcher(running: Bool = true, download: @escaping @Sendable (URL) async throws -> Data = { _ in pngData(size: 4) }) -> ArtworkFetcher {
        ArtworkFetcher(runner: runner, cacheDirectory: cache, isRunning: { _ in running }, download: download)
    }

    func testSpotifyURLIsDownloadedAndCached() async {
        runner.result = .success(.text("https://i.scdn.co/image/x"))
        let fetcher = fetcher()
        let first = await fetcher.artwork(for: makeTrack("a"))
        XCTAssertEqual(first, .image(pngData(size: 4)))
        runner.result = .failure(.failed(-1))
        let second = await fetcher.artwork(for: makeTrack("a"))
        XCTAssertEqual(second, .image(pngData(size: 4)), "second call is served from the cache")
        XCTAssertEqual(runner.sources.count, 1)
    }

    func testMusicDataIsUsedDirectly() async {
        runner.result = .success(.data(pngData(size: 2)))
        let result = await fetcher().artwork(for: makeTrack("00FF", .music))
        XCTAssertEqual(result, .image(pngData(size: 2)))
    }

    /// Review Focus 4.
    func testQuitPlayerIsNeverScripted() async {
        let result = await fetcher(running: false).artwork(for: makeTrack("a"))
        XCTAssertEqual(result, .none)
        XCTAssertTrue(runner.sources.isEmpty)
    }

    /// Review Focus 4: ads report an empty artwork URL.
    func testEmptyArtworkURLIsNone() async {
        runner.result = .success(.text(""))
        let result = await fetcher().artwork(for: makeTrack("spotify:ad:1"))
        XCTAssertEqual(result, .none)
    }

    /// Review Focus 3.
    func testDeniedPermissionIsReported() async {
        runner.result = .failure(.notPermitted)
        let result = await fetcher().artwork(for: makeTrack("a"))
        XCTAssertEqual(result, .notPermitted)
    }

    func testCacheIsPrunedToLimit() async throws {
        runner.result = .success(.data(pngData(size: 1)))
        let fetcher = fetcher()
        for index in 0..<(ArtworkFetcher.cacheLimit + 5) {
            _ = await fetcher.artwork(for: makeTrack("t\(index)", .music))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        XCTAssertEqual(files.count, ArtworkFetcher.cacheLimit)
    }
}
