@testable import Perch
import XCTest

final class PluginIdentifierMigrationTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let migration = PluginIdentifierMigration(from: "org.example.old", to: "org.example.new")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginIdentifierMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PluginIdentifierMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func write(_ text: String, to identifier: String, named name: String = "tasks.json") throws {
        let directory = root.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func read(_ identifier: String, named name: String = "tasks.json") -> String? {
        let url = root.appendingPathComponent(identifier).appendingPathComponent(name)
        return (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func migrate() {
        migration.run(pluginsDirectory: root, defaults: defaults)
    }

    func testStoredFilesMoveToTheNewIdentifier() throws {
        try write("the list", to: "org.example.old")

        migrate()

        XCTAssertEqual(read("org.example.new"), "the list")
        XCTAssertNil(read("org.example.old"))
    }

    /// Anything already under the new identifier is newer. It wins, and the
    /// old files are left where they are rather than deleted.
    func testExistingDataUnderTheNewIdentifierIsNeverOverwritten() throws {
        try write("old list", to: "org.example.old")
        try write("new list", to: "org.example.new")

        migrate()

        XCTAssertEqual(read("org.example.new"), "new list")
        XCTAssertEqual(read("org.example.old"), "old list")
    }

    func testNothingToMigrateIsNotAnError() {
        migrate()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("org.example.new").path))
    }

    func testAMissingPluginsDirectoryIsNotAnError() {
        migration.run(pluginsDirectory: root.appendingPathComponent("nowhere"), defaults: defaults)
    }

    func testTheRegistryKeepsThePluginEnabledActiveAndPrimary() {
        defaults.set(["org.example.other", "org.example.old"], forKey: "enabledPluginIDs")
        defaults.set(["org.example.old", "org.example.other"], forKey: "seenPluginIDs")
        defaults.set("org.example.old", forKey: "activePluginID")
        defaults.set("org.example.old", forKey: "primaryPluginID")

        migrate()

        XCTAssertEqual(defaults.stringArray(forKey: "enabledPluginIDs"), ["org.example.other", "org.example.new"])
        XCTAssertEqual(defaults.stringArray(forKey: "seenPluginIDs"), ["org.example.new", "org.example.other"])
        XCTAssertEqual(defaults.string(forKey: "activePluginID"), "org.example.new")
        XCTAssertEqual(defaults.string(forKey: "primaryPluginID"), "org.example.new")
    }

    func testADisabledPluginStaysDisabled() {
        defaults.set(["org.example.other"], forKey: "enabledPluginIDs")
        defaults.set(["org.example.old", "org.example.other"], forKey: "seenPluginIDs")

        migrate()

        XCTAssertEqual(defaults.stringArray(forKey: "enabledPluginIDs"), ["org.example.other"])
        XCTAssertEqual(defaults.stringArray(forKey: "seenPluginIDs"), ["org.example.new", "org.example.other"])
    }

    func testAnotherPluginsChoicesAreLeftAlone() {
        defaults.set("org.example.other", forKey: "primaryPluginID")

        migrate()

        XCTAssertEqual(defaults.string(forKey: "primaryPluginID"), "org.example.other")
    }

    func testThePluginsOwnSettingsMove() {
        defaults.set(true, forKey: "org.example.old.showDone")
        defaults.set(7, forKey: "org.example.old.limit")
        defaults.set("x", forKey: "org.example.older.unrelated")

        migrate()

        XCTAssertEqual(defaults.object(forKey: "org.example.new.showDone") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "org.example.new.limit") as? Int, 7)
        XCTAssertNil(defaults.object(forKey: "org.example.old.showDone"))
        XCTAssertEqual(defaults.string(forKey: "org.example.older.unrelated"), "x")
    }

    func testRunningTwiceChangesNothingMore() throws {
        try write("the list", to: "org.example.old")
        defaults.set("org.example.old", forKey: "primaryPluginID")

        migrate()
        migrate()

        XCTAssertEqual(read("org.example.new"), "the list")
        XCTAssertEqual(defaults.string(forKey: "primaryPluginID"), "org.example.new")
    }

    func testTheTasksMigrationEndsAtThePluginsIdentifier() {
        XCTAssertEqual(PluginIdentifierMigration.tasks.to, "org.ahlab.perch.tasks")
        XCTAssertNotEqual(PluginIdentifierMigration.tasks.from, PluginIdentifierMigration.tasks.to)
        XCTAssertTrue(PluginIdentifierMigration.tasks.from.hasPrefix("org.ahlab.perch."))
        XCTAssertEqual(PluginIdentifierMigration.tasks.from.count, "org.ahlab.perch.".count + 6)
    }
}
