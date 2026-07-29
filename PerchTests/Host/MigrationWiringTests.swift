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

    // MARK: - The Settings button's actual behaviour

    /// Stands in for the file the user picks in the `NSOpenPanel`.
    private func makeLegacySource(titled title: String) throws -> URL {
        let url = directory.appendingPathComponent("legacy-\(UUID().uuidString).json")
        try JSONEncoder().encode([TodoItem(title: title, sortOrder: 0)]).write(to: url)
        return url
    }

    func testImportingThroughSettingsLeavesTheLivePluginHoldingTheImportedTasks() throws {
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)
        let migration = MigrationState()
        let source = try makeLegacySource(titled: "Imported task")

        let feedback = MenuDoImport.perform(
            from: source, registry: registry, migration: migration, destination: tasksURL
        )

        // The reload is the whole point: without it the plugin still holds [].
        XCTAssertEqual(plugin.store.items.map(\.title), ["Imported task"])
        XCTAssertFalse(feedback.isFailure)
        XCTAssertEqual(migration.notice, MigrationState.importedNotice)

        // And the next save keeps them, rather than destroying them.
        plugin.store.saveNow()
        XCTAssertEqual(MenuDo(context: context).store.items.map(\.title), ["Imported task"])
    }

    func testImportingThroughSettingsWorksAfterAPreviousQuitWroteAnEmptyList() throws {
        // The overwhelmingly common case: Perch has been launched and quit at
        // least once, so an empty list is already sitting at the destination.
        let plugin = MenuDo(context: context)
        plugin.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tasksURL.path))

        let registry = makeRegistry(plugin)
        let source = try makeLegacySource(titled: "Imported task")

        let feedback = MenuDoImport.perform(
            from: source, registry: registry, migration: MigrationState(), destination: tasksURL
        )

        XCTAssertEqual(feedback.message, "Imported — your tasks are in Perch now.")
        XCTAssertEqual(plugin.store.items.map(\.title), ["Imported task"])
    }

    func testImportingThroughSettingsRefusesToTouchARealTaskList() throws {
        let plugin = MenuDo(context: context)
        plugin.store.add("Written in Perch")
        plugin.flush()

        let registry = makeRegistry(plugin)
        let source = try makeLegacySource(titled: "Imported task")

        let feedback = MenuDoImport.perform(
            from: source, registry: registry, migration: MigrationState(), destination: tasksURL
        )

        XCTAssertEqual(feedback.message, "Nothing imported — Perch already has tasks saved.")
        XCTAssertEqual(plugin.store.items.map(\.title), ["Written in Perch"])
    }

    func testAFailedImportSaysSoAndLeavesThePluginAlone() throws {
        let plugin = MenuDo(context: context)
        let registry = makeRegistry(plugin)

        let feedback = MenuDoImport.perform(
            from: directory.appendingPathComponent("no-such-file.json"),
            registry: registry,
            migration: MigrationState(),
            destination: tasksURL
        )

        XCTAssertTrue(feedback.isFailure)
        XCTAssertTrue(plugin.store.items.isEmpty)
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

    func testFlushReachesAPluginTheUserHasDisabled() {
        // Disabling hides a plugin; it does not discard what the user typed
        // just before switching it off. This used to assert the opposite, and
        // the product never behaved that way — TaskStore's own willTerminate
        // subscription flushed a disabled MenuDo regardless.
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
