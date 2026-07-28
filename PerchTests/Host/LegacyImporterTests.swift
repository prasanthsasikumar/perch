@testable import Perch
import XCTest

final class LegacyImporterTests: XCTestCase {
    private var root: URL!
    private var suite: UserDefaults!
    private var suiteName: String!

    private var tasksSource: URL { root.appendingPathComponent("old/tasks.json") }
    private var tasksDestination: URL { root.appendingPathComponent("new/tasks.json") }
    private var preferencesSource: URL { root.appendingPathComponent("old/prefs.plist") }

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: root.appendingPathComponent("old"), withIntermediateDirectories: true
        )
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func writeLegacyTasks(_ contents: String = #"[{"title":"Old task"}]"#) {
        try! Data(contents.utf8).write(to: tasksSource)
    }

    private func writeLegacyPreferences(_ dictionary: [String: Any]) {
        try! NSDictionary(dictionary: dictionary).write(to: preferencesSource)
    }

    // Named `performImport`, not `run`, because this SDK's XCTestCase
    // declares `open func run()`, which would otherwise collide.
    private func performImport() -> LegacyImporter.Result {
        LegacyImporter.run(
            tasksSource: tasksSource,
            tasksDestination: tasksDestination,
            preferencesSource: preferencesSource,
            defaults: suite
        )
    }

    func testNothingToImportIsNotAnError() {
        let result = performImport()
        XCTAssertFalse(result.importedTasks)
        XCTAssertFalse(result.importedPreferences)
    }

    func testTasksAreCopiedNotMoved() {
        writeLegacyTasks()
        let result = performImport()
        XCTAssertTrue(result.importedTasks)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tasksSource.path))
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"Old task"}]"#
        )
    }

    func testImportRunsOnlyOnce() {
        writeLegacyTasks()
        XCTAssertTrue(performImport().importedTasks)

        try! FileManager.default.removeItem(at: tasksDestination)
        XCTAssertFalse(performImport().importedTasks)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tasksDestination.path))
    }

    func testExistingDataIsNeverOverwritten() {
        writeLegacyTasks()
        try! FileManager.default.createDirectory(
            at: tasksDestination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! Data(#"[{"title":"New task"}]"#.utf8).write(to: tasksDestination)

        XCTAssertFalse(performImport().importedTasks)
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"New task"}]"#
        )
    }

    func testFailedTaskCopyDoesNotMarkImportComplete() {
        writeLegacyTasks()
        // Obstruct the destination's parent path with a regular file, so
        // creating the directory there must throw — simulating a transient
        // failure (disk full, permissions, source vanishing mid-copy).
        try! Data().write(to: tasksDestination.deletingLastPathComponent())

        let result = performImport()
        XCTAssertFalse(result.importedTasks)
        XCTAssertFalse(suite.bool(forKey: "legacyImportCompleted"))

        // Clear the obstruction and retry — a transient failure must not be sticky.
        try! FileManager.default.removeItem(at: tasksDestination.deletingLastPathComponent())
        XCTAssertTrue(performImport().importedTasks)
    }

    func testNothingToImportStillMarksComplete() {
        XCTAssertFalse(performImport().importedTasks)
        XCTAssertTrue(suite.bool(forKey: "legacyImportCompleted"))

        // A subsequent run must be a no-op even once a source file appears —
        // the whole point of the flag is to never re-stat the container again.
        writeLegacyTasks()
        XCTAssertFalse(performImport().importedTasks)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tasksDestination.path))
    }

    func testPreferencesAreCarriedAcross() {
        writeLegacyPreferences([
            "showTitleInMenuBar": false,
            "titleTruncationLength": 45,
            "KeyboardShortcuts_openMenuDo": "{\"carbonKeyCode\":1}",
        ])
        let result = performImport()
        XCTAssertTrue(result.importedPreferences)
        XCTAssertEqual(suite.object(forKey: "showTitleInMenuBar") as? Bool, false)
        XCTAssertEqual(suite.object(forKey: "titleTruncationLength") as? Int, 45)
        XCTAssertEqual(
            suite.string(forKey: "KeyboardShortcuts_openPerch"),
            "{\"carbonKeyCode\":1}"
        )
    }

    func testAbsentPreferenceKeysAreLeftAlone() {
        writeLegacyPreferences(["titleTruncationLength": 45])
        XCTAssertTrue(performImport().importedPreferences)
        XCTAssertNil(suite.object(forKey: "showTitleInMenuBar"))
        XCTAssertNil(suite.object(forKey: "KeyboardShortcuts_openPerch"))
    }

    func testPreferencesAlreadySetLocallyWin() {
        suite.set(20, forKey: "titleTruncationLength")
        writeLegacyPreferences(["titleTruncationLength": 45])
        _ = performImport()
        XCTAssertEqual(suite.object(forKey: "titleTruncationLength") as? Int, 20)
    }

    func testLegacyPathsPointAtTheOldContainer() {
        XCTAssertTrue(
            LegacyImporter.legacyTasksURL.path.hasSuffix(
                "Library/Containers/org.ahlab.MenuDo/Data/Library/Application Support/MenuDo/tasks.json"
            )
        )
        XCTAssertTrue(
            LegacyImporter.legacyPreferencesURL.path.hasSuffix(
                "Library/Containers/org.ahlab.MenuDo/Data/Library/Preferences/org.ahlab.MenuDo.plist"
            )
        )
        // Sandboxed, NSHomeDirectory() is the container — the importer must not use it.
        XCTAssertFalse(LegacyImporter.legacyTasksURL.path.contains("org.ahlab.Perch"))
    }
}
