@testable import SpinPlugin
import XCTest

final class ScriptRunnerTests: XCTestCase {
    /// Final review 4: cancelling a caller must keep its queued script from
    /// ever being sent, so disabling Spin stops Apple Events already waiting.
    func testCancelledQueuedScriptNeverRuns() async throws {
        let gate = DispatchSemaphore(value: 0)
        let ran = LockedList()
        let runner = NSAppleScriptRunner { source in
            if source == "first" { gate.wait() }
            ran.append(source)
            return .none
        }
        let first = Task { try await runner.run("first") }
        try await Task.sleep(for: .milliseconds(50))
        let second = Task { try await runner.run("second") }
        try await Task.sleep(for: .milliseconds(50))
        second.cancel()
        gate.signal()
        _ = try await first.value
        do {
            _ = try await second.value
            XCTFail("a cancelled script should throw")
        } catch is CancellationError {}
        XCTAssertEqual(ran.items, ["first"])
    }
}

final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [String] = []
    var items: [String] { lock.withLock { _items } }
    func append(_ item: String) { lock.withLock { _items.append(item) } }
}
