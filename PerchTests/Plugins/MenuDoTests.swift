import MenuDoPlugin
import PerchKit
import XCTest

@MainActor
final class MenuDoTests: XCTestCase {
    private func makePlugin() -> MenuDo {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        return MenuDo(
            context: PluginContext(
                storage: PluginStorage(directory: directory),
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "PerchTests-\(UUID().uuidString)")!,
                    prefix: "org.ahlab.perch.menudo"
                )
            )
        )
    }

    func testMetadata() {
        XCTAssertEqual(MenuDo.identifier, "org.ahlab.perch.menudo")
        XCTAssertEqual(MenuDo.displayName, "Tasks")
        XCTAssertEqual(MenuDo.icon, "checkmark.circle")
        XCTAssertTrue(MenuDo.capabilities.isEmpty)
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
