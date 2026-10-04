@testable import SpinPlugin
import PerchKit
import XCTest

@MainActor
final class SpinPluginTests: XCTestCase {
    private func makeSpin() -> Spin {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = PluginContext(
            storage: PluginStorage(directory: dir),
            defaults: PluginDefaults(suite: UserDefaults(suiteName: UUID().uuidString)!, prefix: Spin.identifier)
        )
        return Spin(context: context, scenes: SceneCatalog.builtIn, artwork: FakeArtwork(), query: FakeQuery())
    }

    func testMetadata() {
        XCTAssertEqual(Spin.identifier, "org.ahlab.perch.spin")
        XCTAssertEqual(Spin.displayName, "Spin")
        XCTAssertEqual(Spin.capabilities, [.network, .media])
    }

    func testMenuBarShowsTrackOnlyWhilePlaying() {
        let spin = makeSpin()
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle"))
        spin.model.receive(PlayerEvent(player: .spotify, state: .playing, track: makeTrack("a")))
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle", text: "Title a – Artist"))
        spin.model.receive(PlayerEvent(player: .spotify, state: .paused, track: makeTrack("a")))
        XCTAssertEqual(spin.menuBarLabel, MenuBarLabel(systemImage: "record.circle"))
    }

    func testDisablingResetsTheModel() {
        let spin = makeSpin()
        spin.setEnabled(true)
        spin.model.receive(PlayerEvent(player: .spotify, state: .playing, track: makeTrack("a")))
        spin.setEnabled(false)
        XCTAssertNil(spin.model.nowPlaying)
    }
}
