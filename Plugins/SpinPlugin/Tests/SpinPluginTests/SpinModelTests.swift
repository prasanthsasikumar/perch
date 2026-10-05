@testable import SpinPlugin
import PerchKit
import XCTest

@MainActor
final class SpinModelTests: XCTestCase {
    private var suite: UserDefaults!
    private let artwork = FakeArtwork()
    private let query = FakeQuery()
    private let clock = TestClock()
    private let scene = SceneAsset(
        descriptor: SceneDescriptor(
            id: "room", name: "Room", order: 0,
            platter: .init(x: 0.5, y: 0.5, radius: 0.1, squash: 0.4), tonearm: nil,
            sleeve: .init(x: 0.2, y: 0.5, size: 0.2, rotation: 0, style: .stand)
        ),
        backgroundURL: URL(fileURLWithPath: "/dev/null"), thumbnailURL: URL(fileURLWithPath: "/dev/null")
    )

    override func setUp() {
        suite = UserDefaults(suiteName: UUID().uuidString)
    }

    private func model(showsScene: Bool = true) -> SpinModel {
        let defaults = PluginDefaults(suite: suite, prefix: "spin")
        defaults.set(showsScene, for: "showsScene")
        let clock = clock
        return SpinModel(defaults: defaults, scenes: [scene], artworkProvider: artwork, query: query, now: { clock.now })
    }

    private func playing(_ id: String) -> PlayerEvent {
        PlayerEvent(player: .spotify, state: .playing, track: makeTrack(id))
    }

    private func paused(_ id: String) -> PlayerEvent {
        PlayerEvent(player: .spotify, state: .paused, track: makeTrack(id))
    }

    func testShowsSceneDefaultsOff() {
        let model = SpinModel(defaults: PluginDefaults(suite: suite, prefix: "fresh"), scenes: [scene],
                              artworkProvider: artwork, query: query)
        XCTAssertFalse(model.showsScene)
        model.receive(playing("a"))
        XCTAssertFalse(model.wantsWindow)
    }

    func testPlayingShowsSpinningScene() async {
        let model = model()
        model.receive(playing("a"))
        XCTAssertEqual(model.phase, .spinning)
        XCTAssertTrue(model.wantsWindow)
        XCTAssertTrue(model.isAnimating)
    }

    func testPauseRestsThenHidesAfterLinger() {
        let model = model()
        model.receive(playing("a"))
        clock.advance(3600)
        model.receive(paused("a"))
        XCTAssertEqual(model.phase, .resting)
        clock.advance(SceneVisibility.linger + 1)
        model.reevaluate()
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.wantsWindow)
    }

    func testArtworkLoadsForTrack() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .loaded)
        XCTAssertEqual(model.artwork?.representations.first?.pixelsWide, 3)
    }

    /// Review Focus 2.
    func testStaleArtworkIsDiscarded() async {
        artwork.results["a"] = .image(pngData(size: 2))
        artwork.delays["a"] = .milliseconds(200)
        artwork.results["b"] = .image(pngData(size: 5))
        let model = model()
        model.receive(playing("a"))
        model.receive(playing("b"))
        await model.settle()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.artwork?.representations.first?.pixelsWide, 5)
    }

    /// Review Focus 3.
    func testNotPermittedStatus() async {
        artwork.results["a"] = .notPermitted
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .notPermitted)
        XCTAssertNil(model.artwork)
    }

    func testNoScriptingWhileSceneIsOff() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model(showsScene: false)
        model.receive(playing("a"))
        model.activate()
        await model.settle()
        XCTAssertNil(model.artwork)
        XCTAssertTrue(query.asked.isEmpty)
    }

    func testTurningSceneOnFetchesArtAndPrimes() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model(showsScene: false)
        model.receive(playing("a"))
        model.showsScene = true
        await model.settle()
        XCTAssertEqual(model.artworkStatus, .loaded)
        XCTAssertEqual(Set(query.asked), Set(Player.allCases))
    }

    func testActivatePrimesFromRunningPlayers() async {
        query.events[.music] = PlayerEvent(player: .music, state: .playing, track: makeTrack("m", .music))
        let model = model()
        model.activate()
        await model.settle()
        XCTAssertEqual(model.nowPlaying?.player, .music)
    }

    func testPingRefreshesFromQuery() async {
        query.events[.spotify] = playing("z")
        let model = model()
        model.refresh(.spotify)
        await model.settle()
        XCTAssertEqual(model.nowPlaying?.track?.id, "z")
    }

    /// Review Focus 5.
    func testTogglingSceneOffHidesWindow() {
        let model = model()
        model.receive(playing("a"))
        model.showsScene = false
        XCTAssertFalse(model.wantsWindow)
    }

    /// Review Focus 5.
    func testResetClearsEverything() async {
        artwork.results["a"] = .image(pngData(size: 3))
        let model = model()
        model.receive(playing("a"))
        await model.settle()
        model.reset()
        XCTAssertNil(model.nowPlaying)
        XCTAssertNil(model.artwork)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertFalse(model.wantsWindow)
    }

    func testSelectedScenePersists() {
        let first = model()
        first.selectedSceneID = "room"
        XCTAssertEqual(model().selectedSceneID, "room")
    }

    /// Final review 4: turning the scene off stops in-flight Apple Events work.
    func testTurningSceneOffCancelsArtworkFetch() async {
        artwork.results["a"] = .image(pngData(size: 3))
        artwork.delays["a"] = .milliseconds(200)
        let model = model()
        model.receive(playing("a"))
        model.showsScene = false
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.artwork)
        XCTAssertNotEqual(model.artworkStatus, .loaded)
    }
}
