import MenuDoPlugin
@testable import Perch
import PerchKit
import XCTest

/// The seams between the host and a plugin.
///
/// Every piece involved here is already covered on its own: the importer knows
/// how to copy a file, the store knows how to save, the registry knows which
/// plugins are enabled. The bug that got through was entirely in the wiring —
/// the host changed a plugin's file and never told the plugin — so these tests
/// exercise the two units together and assert on what ends up on disk.
@MainActor
final class MigrationWiringTests: XCTestCase {
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

    /// Exactly what `LegacyImporter` does: drop a task file into the plugin's
    /// storage directory, with the plugin already running.
    private func copyLegacyTasksIn(titled title: String) throws {
        try JSONEncoder()
            .encode([TodoItem(title: title, sortOrder: 0)])
            .write(to: tasksURL)
    }

    private func makeRegistry(_ plugin: MenuDo) -> PluginRegistry {
        PluginRegistry(plugins: [plugin], defaults: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - The manual import must not be destroyed by the live plugin

    func testImportedFileSurvivesThePluginsNextSave() throws {
        // The automatic import found nothing, so the plugin loaded an empty list.
        let plugin = MenuDo(context: context)
        XCTAssertTrue(plugin.store.items.isEmpty)

        try copyLegacyTasksIn(titled: "Imported task")
        // What the host owes a plugin whose storage it just changed.
        plugin.reload()
        // What happens next in real life: the quit flush, or any mutation's
        // debounced save. Without the reload above this writes [] over the
        // file that was just imported, and the user is told their data is safe.
        plugin.store.saveNow()

        XCTAssertEqual(MenuDo(context: context).store.items.map(\.title), ["Imported task"])
    }

    func testTheHostReloadsThroughTheRegistryByIdentifier() throws {
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)
        try copyLegacyTasksIn(titled: "Imported task")

        // The call Settings makes after a successful manual import.
        registry.reload(id: MenuDo.identifier)
        plugin.store.saveNow()

        XCTAssertEqual(MenuDo(context: context).store.items.map(\.title), ["Imported task"])
    }

    func testReloadingAnUnknownIdentifierIsHarmless() {
        let registry = makeRegistry(MenuDo(context: context))
        registry.reload(id: "org.ahlab.perch.nonexistent")
    }

    // MARK: - Quit must flush

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

    func testFlushLeavesADisabledPluginsFileAlone() {
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)
        plugin.store.add("Unsaved")
        registry.setEnabled(false, for: MenuDo.identifier)

        registry.flushAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tasksURL.path))
    }

    // MARK: - The importer's destination and the plugin's file are the same file

    func testImporterDestinationIsWhereTheHostGivesMenuDoItsStorage() {
        XCTAssertTrue(
            LegacyImporter.menuDoTasksDestination.path.hasSuffix(
                "Application Support/Perch/Plugins/org.ahlab.perch.menudo/tasks.json"
            ),
            "got \(LegacyImporter.menuDoTasksDestination.path)"
        )
    }

    func testMenuDoWritesTheExactFilenameTheImporterTargets() throws {
        let plugin = MenuDo(context: context)
        plugin.store.add("A")
        plugin.flush()

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [LegacyImporter.menuDoTasksDestination.lastPathComponent]
        )
    }
}
