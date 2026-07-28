import XCTest
@testable import Perch

@MainActor
final class TaskStoreLogicTests: XCTestCase {
    private var fileURL: URL!
    private var store: TaskStore!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = dir.appendingPathComponent("tasks.json")
        store = TaskStore(fileURL: fileURL)
    }

    func testAddAppendsTrimmedPendingTask() {
        store.add("  Buy milk  ")
        XCTAssertEqual(store.pending.map(\.title), ["Buy milk"])
    }

    func testAddIgnoresEmptyAndWhitespaceTitles() {
        store.add("")
        store.add("   ")
        XCTAssertTrue(store.items.isEmpty)
    }

    func testCurrentTaskIsFirstIncompleteBySortOrder() {
        store.add("First")
        store.add("Second")
        XCTAssertEqual(store.currentTask?.title, "First")
        store.toggle(store.currentTask!.id)
        XCTAssertEqual(store.currentTask?.title, "Second")
    }

    func testToggleMovesTaskBetweenPendingAndDone() {
        store.add("A")
        let id = store.pending[0].id
        store.toggle(id)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.done.map(\.title), ["A"])
        store.toggle(id)
        XCTAssertEqual(store.pending.map(\.title), ["A"])
    }

    func testDeleteRemovesTask() {
        store.add("A")
        store.add("B")
        store.delete(store.pending[0].id)
        XCTAssertEqual(store.pending.map(\.title), ["B"])
    }

    func testMovePendingReordersAndRenumbers() {
        store.add("A")
        store.add("B")
        store.add("C")
        store.movePending(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.pending.map(\.title), ["C", "A", "B"])
        XCTAssertEqual(store.pending.map(\.sortOrder), [0, 1, 2])
    }

    func testClearCompletedRemovesOnlyDoneTasks() {
        store.add("A")
        store.add("B")
        store.toggle(store.pending[0].id)
        store.clearCompleted()
        XCTAssertEqual(store.items.map(\.title), ["B"])
    }

    func testMovePendingAfterToggleKeepsUniqueSortOrders() {
        store.add("A")
        store.add("B")
        store.add("C")
        let bID = store.pending[1].id
        store.toggle(bID)
        store.movePending(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        store.toggle(bID)
        XCTAssertEqual(Set(store.items.map(\.sortOrder)).count, store.items.count)
        XCTAssertEqual(store.pending.map(\.title), ["C", "A", "B"])
    }

    func testRenameUpdatesMatchingTaskOnly() {
        store.add("A")
        store.add("B")
        store.rename(store.pending[0].id, to: "A renamed")
        XCTAssertEqual(store.pending.map(\.title), ["A renamed", "B"])
    }

    func testRenameTrimsWhitespace() {
        store.add("A")
        store.rename(store.pending[0].id, to: "  Buy oat milk  ")
        XCTAssertEqual(store.pending[0].title, "Buy oat milk")
    }

    func testRenameIgnoresEmptyAndWhitespaceTitles() {
        store.add("A")
        let id = store.pending[0].id
        store.rename(id, to: "")
        store.rename(id, to: "   ")
        XCTAssertEqual(store.pending[0].title, "A")
    }

    func testRenameIgnoresUnknownID() {
        store.add("A")
        store.rename(UUID(), to: "Nope")
        XCTAssertEqual(store.items.map(\.title), ["A"])
    }

    func testRenameUpdatesCurrentTask() {
        store.add("First")
        store.add("Second")
        store.rename(store.currentTask!.id, to: "First renamed")
        XCTAssertEqual(store.currentTask?.title, "First renamed")
    }

    func testRenamePreservesIdentityAndPosition() {
        store.add("A")
        store.add("B")
        store.toggle(store.pending[1].id)
        let original = store.done[0]
        store.rename(original.id, to: "B renamed")
        let renamed = store.done[0]
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.isDone, original.isDone)
        XCTAssertEqual(renamed.sortOrder, original.sortOrder)
        XCTAssertEqual(renamed.createdAt, original.createdAt)
        XCTAssertEqual(renamed.title, "B renamed")
    }
}
