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
        // Some tests revoke read permission to stand in for a sandbox denial;
        // put it back, or the temp tree can't be deleted.
        restorePermissions()
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func setPermissions(_ mode: Int, on url: URL) {
        try! FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: url.path
        )
    }

    private func restorePermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("old").path
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: tasksSource.path
        )
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

    func testOutcomeDistinguishesAlreadyHasDataFromFailure() {
        // The Settings import button needs these two outcomes to read as
        // different messages: one says the data is already safe, the other
        // must never claim that when it isn't true.
        writeLegacyTasks()
        try! FileManager.default.createDirectory(
            at: tasksDestination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! Data(#"[{"title":"New task"}]"#.utf8).write(to: tasksDestination)

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .alreadyHasData
        )
    }

    func testOutcomeReportsGenuineFailureDistinctly() {
        writeLegacyTasks()
        // Obstruct the destination's parent path with a regular file, so
        // creating the directory there must throw — simulating a transient
        // failure (disk full, permissions, source vanishing mid-copy).
        try! Data().write(to: tasksDestination.deletingLastPathComponent())

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .failed
        )

        // Clear the obstruction — a genuine failure must not be sticky.
        try! FileManager.default.removeItem(at: tasksDestination.deletingLastPathComponent())
        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .imported
        )
    }

    func testOutcomeReportsNothingToImportWhenSourceIsMissing() {
        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .nothingToImport
        )
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

    // MARK: - "The destination has data" must mean data, not a file

    private func writeDestination(_ contents: String) {
        try! FileManager.default.createDirectory(
            at: tasksDestination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! Data(contents.utf8).write(to: tasksDestination)
    }

    func testAnEmptyDestinationIsImportedOver() {
        // What a fresh Perch writes to this exact path the first time it quits.
        // Treating it as "already has data" strands every user who has launched
        // and quit once — which is all of them.
        writeLegacyTasks()
        writeDestination("[]")

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .imported
        )
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"Old task"}]"#
        )
    }

    func testTheAutomaticRetryStillSucceedsAfterAQuitWroteAnEmptyList() {
        // Path A end to end. Launch 1: the source is refused, so the import
        // fails and is left to be retried.
        writeLegacyTasks()
        setPermissions(0, on: root.appendingPathComponent("old"))
        XCTAssertFalse(performImport().importedTasks)
        XCTAssertFalse(suite.bool(forKey: "legacyImportCompleted"))

        // The user quits. Every flush path writes the empty in-memory list.
        writeDestination("[]")

        // Launch 2: access restored, and the retry must actually carry the
        // tasks across rather than being turned away by its own leftovers.
        restorePermissions()
        XCTAssertTrue(performImport().importedTasks)
        XCTAssertTrue(suite.bool(forKey: "legacyImportCompleted"))
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"Old task"}]"#
        )
    }

    func testARealTaskListIsStillNeverOverwritten() {
        writeLegacyTasks()
        writeDestination(#"[{"title":"New task"}]"#)

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .alreadyHasData
        )
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"New task"}]"#
        )
    }

    func testAnUndecodableDestinationCountsAsDataAndIsLeftAlone() {
        // Might be a corrupt task list. Overwriting it would be exactly the
        // unforgivable loss this importer exists to prevent.
        writeLegacyTasks()
        writeDestination("not json at all")

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .alreadyHasData
        )
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            "not json at all"
        )
    }

    // MARK: - "It isn't there" vs "I was refused"

    func testSourceStateTellsAnAbsentFileFromAnUnreadableOne() {
        XCTAssertEqual(LegacyImporter.sourceState(of: tasksSource), .absent)

        writeLegacyTasks()
        XCTAssertEqual(LegacyImporter.sourceState(of: tasksSource), .present)

        // Metadata still visible, bytes refused — what `FileManager.fileExists`
        // would happily report as `false`, i.e. as "there is nothing to import".
        setPermissions(0, on: tasksSource)
        XCTAssertEqual(LegacyImporter.sourceState(of: tasksSource), .unreadable)
    }

    func testAnUnreadableContainerIsNotMistakenForAnAbsentFile() {
        writeLegacyTasks()
        // The likelier shape of a sandbox denial: the whole container is
        // off-limits, so even stat() fails.
        setPermissions(0, on: root.appendingPathComponent("old"))
        XCTAssertEqual(LegacyImporter.sourceState(of: tasksSource), .unreadable)
    }

    func testARefusedSourceIsRetriedRatherThanWrittenOffAsNothingToImport() {
        writeLegacyTasks()
        // Revoking the containing directory, not the file: that is the shape a
        // sandbox denial takes, and the one `FileManager.fileExists` used to
        // report as a plain `false` — indistinguishable from "no legacy data".
        setPermissions(0, on: root.appendingPathComponent("old"))

        XCTAssertEqual(
            LegacyImporter.importTasksOutcome(from: tasksSource, to: tasksDestination),
            .failed
        )
        XCTAssertFalse(performImport().importedTasks)
        // The whole point: `.nothingToImport` would set this permanently, and
        // the user would never get another automatic attempt.
        XCTAssertFalse(suite.bool(forKey: "legacyImportCompleted"))

        // Access restored — as it would be by a fixed entitlement or a later
        // macOS — and the next launch carries the tasks across.
        restorePermissions()
        XCTAssertTrue(performImport().importedTasks)
    }

    func testResultCarriesTheOutcomeSoTheAppCanExplainAFailure() {
        writeLegacyTasks()
        setPermissions(0, on: root.appendingPathComponent("old"))
        // Important 3: `importedTasks == false` alone can't tell the app
        // whether to stay quiet or point the user at the manual fallback.
        XCTAssertEqual(performImport().taskOutcome, .failed)

        restorePermissions()
        XCTAssertEqual(performImport().taskOutcome, .imported)
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
