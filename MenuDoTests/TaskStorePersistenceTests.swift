import XCTest
@testable import MenuDo

@MainActor
final class TaskStorePersistenceTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuDoTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")
    }

    func testMissingFileLoadsEmptyWithoutNotice() {
        let store = TaskStore(fileURL: fileURL)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.loadFailureNotice)
    }

    func testSaveNowThenReloadRoundTrips() {
        let store = TaskStore(fileURL: fileURL)
        store.add("A")
        store.add("B")
        store.toggle(store.pending[1].id)
        store.saveNow()

        let reloaded = TaskStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.pending.map(\.title), ["A"])
        XCTAssertEqual(reloaded.done.map(\.title), ["B"])
        XCTAssertNil(reloaded.loadFailureNotice)
    }

    func testCorruptFileBacksUpAndStartsEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        let store = TaskStore(fileURL: fileURL)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.loadFailureNotice, "Couldn't read saved tasks — backup kept")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("bak").path)
        )
    }

    func testMutationTriggersDebouncedSave() async throws {
        let store = TaskStore(fileURL: fileURL)
        store.add("A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSaveNowCancelsPendingDebouncedSave() async throws {
        let store = TaskStore(fileURL: fileURL)
        store.add("A")
        store.saveNow()
        try FileManager.default.removeItem(at: fileURL)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
