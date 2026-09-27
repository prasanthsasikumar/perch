import TasksPlugin
import PerchKit
import XCTest

@MainActor
final class TasksTests: XCTestCase {
    private func makePlugin() -> Tasks {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        return Tasks(
            context: PluginContext(
                storage: PluginStorage(directory: directory),
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "PerchTests-\(UUID().uuidString)")!,
                    prefix: "org.ahlab.perch.tasks"
                )
            )
        )
    }

    func testMetadata() {
        XCTAssertEqual(Tasks.identifier, "org.ahlab.perch.tasks")
        XCTAssertEqual(Tasks.displayName, "Tasks")
        XCTAssertEqual(Tasks.icon, "checkmark.circle")
        XCTAssertTrue(Tasks.capabilities.isEmpty)
    }

    func testMenuBarLabelIsIconOnlyWithNoTasks() {
        let plugin = makePlugin()
        XCTAssertEqual(plugin.menuBarLabel?.systemImage, "checkmark.circle")
        XCTAssertNil(plugin.menuBarLabel?.text)
    }

    func testMenuBarLabelShowsTheCurrentTask() {
        let plugin = makePlugin()
        plugin.store.add("Write the spec")
        plugin.store.add("Ship it")
        XCTAssertEqual(plugin.menuBarLabel?.text, "Write the spec")
    }

    func testMenuBarLabelAdvancesWhenTheCurrentTaskIsCompleted() {
        let plugin = makePlugin()
        plugin.store.add("First")
        plugin.store.add("Second")
        plugin.store.toggle(plugin.store.currentTask!.id)
        XCTAssertEqual(plugin.menuBarLabel?.text, "Second")
    }

    func testNoFooterActionUntilSomethingIsDone() {
        let plugin = makePlugin()
        plugin.store.add("A")
        XCTAssertTrue(plugin.footerActions.isEmpty)
    }

    func testClearCompletedActionAppearsAndWorks() {
        let plugin = makePlugin()
        plugin.store.add("A")
        plugin.store.toggle(plugin.store.pending[0].id)

        XCTAssertEqual(plugin.footerActions.map(\.title), ["Clear completed"])
        plugin.footerActions[0].perform()
        XCTAssertTrue(plugin.store.done.isEmpty)
    }
}
