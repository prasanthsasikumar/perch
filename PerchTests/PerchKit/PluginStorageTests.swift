import PerchKit
import XCTest

private struct Note: Codable, Equatable {
    var text: String
}

final class PluginStorageTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testLoadingAMissingFileReturnsNil() throws {
        let storage = PluginStorage(directory: directory)
        XCTAssertNil(try storage.load(Note.self, named: "note.json"))
    }

    func testSaveCreatesTheDirectoryAndRoundTrips() throws {
        let storage = PluginStorage(directory: directory)
        try storage.save(Note(text: "hello"), named: "note.json")
        XCTAssertEqual(try storage.load(Note.self, named: "note.json"), Note(text: "hello"))
    }

    func testUnreadableFileIsBackedUpAndThrows() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("note.json")
        try Data("not json".utf8).write(to: fileURL)

        let storage = PluginStorage(directory: directory)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json")) { error in
            XCTAssertEqual(error as? PluginStorageError, .unreadable)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("bak").path)
        )
    }

    func testBackupIsReplacedOnASecondFailure() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("note.json")
        let storage = PluginStorage(directory: directory)

        try Data("first".utf8).write(to: fileURL)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json"))
        try Data("second".utf8).write(to: fileURL)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json"))

        let backup = try Data(contentsOf: fileURL.appendingPathExtension("bak"))
        XCTAssertEqual(String(decoding: backup, as: UTF8.self), "second")
    }

    func testTwoPluginDirectoriesDoNotSeeEachOther() throws {
        let a = PluginStorage(directory: directory.appendingPathComponent("org.ahlab.perch.a"))
        let b = PluginStorage(directory: directory.appendingPathComponent("org.ahlab.perch.b"))
        try a.save(Note(text: "a"), named: "note.json")
        XCTAssertNil(try b.load(Note.self, named: "note.json"))
        XCTAssertEqual(try a.load(Note.self, named: "note.json"), Note(text: "a"))
    }
}
