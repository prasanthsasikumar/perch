import XCTest
import MenuDoPlugin

final class TodoItemTests: XCTestCase {
    func testDefaults() {
        let item = TodoItem(title: "Buy milk", sortOrder: 0)
        XCTAssertFalse(item.isDone)
        XCTAssertEqual(item.title, "Buy milk")
        XCTAssertEqual(item.sortOrder, 0)
    }

    func testCodableRoundTrip() throws {
        let item = TodoItem(title: "Buy milk", isDone: true, sortOrder: 3)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TodoItem.self, from: data)
        XCTAssertEqual(item, decoded)
    }

    func testDistinctIdsByDefault() {
        XCTAssertNotEqual(
            TodoItem(title: "A", sortOrder: 0).id,
            TodoItem(title: "B", sortOrder: 1).id
        )
    }
}
