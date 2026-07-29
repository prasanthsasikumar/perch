import MenuDoPlugin
@testable import Perch
import PerchKit
import XCTest

/// The seam between the host's quit path and a plugin's unsaved state.
///
/// Both halves are covered on their own — the store knows how to save, the
/// registry knows which plugins are enabled — but `PerchPlugin.flush()` is a
/// promise the *host* makes, and only exercising them together proves it is
/// kept. These assert on what ends up on disk, not on what was called.
@MainActor
final class PluginFlushTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var context: PluginContext!

    private var tasksURL: URL { directory.appendingPathComponent(MenuDo.tasksFilename) }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PerchTests-\(UUID().uuidString)"
        context = PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(
                suite: UserDefaults(suiteName: suiteName)!, prefix: MenuDo.identifier
            )
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRegistry(_ plugin: MenuDo) -> PluginRegistry {
        PluginRegistry(plugins: [plugin], defaults: UserDefaults(suiteName: suiteName)!)
    }

    func testFlushAllPersistsWorkThePluginHadNotWrittenYet() {
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)
        plugin.store.add("Typed just before quitting")
        // The store debounces, so nothing has reached disk.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tasksURL.path))

        // What PanelView.quit() does before NSApp.terminate.
        registry.flushAll()

        XCTAssertEqual(
            MenuDo(context: context).store.items.map(\.title), ["Typed just before quitting"]
        )
    }

    func testFlushReachesAPluginTheUserHasDisabled() {
        // Disabling hides a plugin; it does not discard what the user typed
        // just before switching it off.
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)
        plugin.store.add("Typed before switching the plugin off")
        registry.setEnabled(false, for: MenuDo.identifier)

        registry.flushAll()

        XCTAssertEqual(
            MenuDo(context: context).store.items.map(\.title),
            ["Typed before switching the plugin off"]
        )
    }

    /// The host builds every plugin's context through one helper, so a plugin
    /// and anything else reaching for its storage cannot drift apart.
    func testHostGivesMenuDoStorageNamespacedByItsIdentifier() {
        let storage = PluginContext.perch(MenuDo.identifier).storage
        XCTAssertTrue(
            storage.directory.path.hasSuffix("Perch/Plugins/\(MenuDo.identifier)"),
            "unexpected storage directory: \(storage.directory.path)"
        )
    }

    func testMenuDoWritesTheFilenameItDeclares() throws {
        let plugin = MenuDo(context: context)
        plugin.store.add("A task")
        plugin.flush()

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(written, [MenuDo.tasksFilename])
    }
}
