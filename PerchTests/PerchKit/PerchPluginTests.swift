import Observation
import PerchKit
import SwiftUI
import XCTest

@MainActor
@Observable
private final class StubPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.stub"
    static let displayName = "Stub"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = [.network]

    var count = 0

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(Text("stub")) }
    var menuBarLabel: MenuBarLabel? { MenuBarLabel(systemImage: "circle", text: "\(count)") }
}

@MainActor
@Observable
private final class BarePlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.bare"
    static let displayName = "Bare"
    static let icon = "square"
    static let capabilities: Set<PluginCapability> = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
final class PerchPluginTests: XCTestCase {
    private func makeContext(_ identifier: String) -> PluginContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        return PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(suite: UserDefaults(suiteName: identifier)!, prefix: identifier)
        )
    }

    func testStaticMetadataIsReadableThroughAnExistential() {
        let plugins: [any PerchPlugin] = [
            StubPlugin(context: makeContext("stub")),
            BarePlugin(context: makeContext("bare")),
        ]
        XCTAssertEqual(plugins.map(\.identifier), ["org.ahlab.perch.stub", "org.ahlab.perch.bare"])
        XCTAssertEqual(plugins.map(\.displayName), ["Stub", "Bare"])
        XCTAssertEqual(plugins.map(\.icon), ["circle", "square"])
        XCTAssertEqual(plugins[0].capabilities, [.network])
        XCTAssertEqual(plugins[1].capabilities, [])
    }

    func testDefaultsAreSuppliedForOptionalRequirements() {
        let plugin: any PerchPlugin = BarePlugin(context: makeContext("bare"))
        XCTAssertNil(plugin.menuBarLabel)
        XCTAssertTrue(plugin.footerActions.isEmpty)
    }

    func testMenuBarLabelReflectsPluginState() {
        let plugin = StubPlugin(context: makeContext("stub"))
        XCTAssertEqual(plugin.menuBarLabel?.text, "0")
        plugin.count = 5
        XCTAssertEqual(plugin.menuBarLabel?.text, "5")
    }

    func testStandardContextNamespacesByIdentifier() {
        let context = PluginContext.standard(appName: "Perch", identifier: "org.ahlab.perch.stub")
        XCTAssertTrue(
            context.storage.directory.path.hasSuffix("Perch/Plugins/org.ahlab.perch.stub")
        )
    }
}
