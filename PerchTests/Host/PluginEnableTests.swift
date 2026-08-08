import PerchKit
@testable import Perch
import SwiftUI
import XCTest

/// A plugin that records every enable/disable it is told about.
@MainActor
@Observable
private final class RecordingPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.recording"
    static let displayName = "Recording"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = []

    var calls: [Bool] = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }

    func setEnabled(_ isEnabled: Bool) { calls.append(isEnabled) }
}

/// A second one, so we can prove only the changed plugin is notified.
@MainActor
@Observable
private final class OtherRecordingPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.recording.other"
    static let displayName = "Other"
    static let icon = "square"
    static let capabilities: Set<PluginCapability> = []

    var calls: [Bool] = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }

    func setEnabled(_ isEnabled: Bool) { calls.append(isEnabled) }
}

@MainActor
final class PluginEnableTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PluginEnableTests-\(UUID().uuidString)")!
    }

    private func context(_ identifier: String) -> PluginContext {
        PluginContext(
            storage: PluginStorage(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PluginEnableTests-\(UUID().uuidString)")
            ),
            defaults: PluginDefaults(suite: makeDefaults(), prefix: identifier)
        )
    }

    func testAPluginIsToldItIsEnabledAtStartup() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))

        _ = PluginRegistry(plugins: [plugin], defaults: makeDefaults())

        XCTAssertEqual(plugin.calls, [true])
    }

    func testAPluginStoredAsDisabledIsToldSoAtStartup() {
        let defaults = makeDefaults()
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        // Both known to this install, only `other` switched on.
        defaults.set([RecordingPlugin.identifier, OtherRecordingPlugin.identifier],
                     forKey: "seenPluginIDs")
        defaults.set([OtherRecordingPlugin.identifier], forKey: "enabledPluginIDs")

        _ = PluginRegistry(plugins: [plugin, other], defaults: defaults)

        XCTAssertEqual(plugin.calls, [false])
        XCTAssertEqual(other.calls, [true])
    }

    /// The subtle case `PluginRegistry`'s own comment calls out: a plugin
    /// present in this build but absent from both `seenPluginIDs` and
    /// `enabledPluginIDs` looks, from stored state alone, indistinguishable
    /// from one the user turned off — except it never existed for them to
    /// turn off. It must default to enabled, the same as a genuinely fresh
    /// install.
    func testAPluginNewToThisBuildIsToldItIsEnabledAtStartup() {
        let defaults = makeDefaults()
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        // Only `other` was known to this install before the upgrade that
        // added `plugin`.
        defaults.set([OtherRecordingPlugin.identifier], forKey: "seenPluginIDs")
        defaults.set([OtherRecordingPlugin.identifier], forKey: "enabledPluginIDs")

        _ = PluginRegistry(plugins: [plugin, other], defaults: defaults)

        XCTAssertEqual(plugin.calls, [true])
    }

    func testDisablingNotifiesThePlugin() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        plugin.calls.removeAll()
        other.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertEqual(plugin.calls, [false])
    }

    func testOnlyTheChangedPluginIsNotified() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        plugin.calls.removeAll()
        other.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertTrue(other.calls.isEmpty)
    }

    func testReEnablingNotifiesThePlugin() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        registry.setEnabled(false, for: RecordingPlugin.identifier)
        plugin.calls.removeAll()

        registry.setEnabled(true, for: RecordingPlugin.identifier)

        XCTAssertEqual(plugin.calls, [true])
    }

    func testSettingTheSameStateTwiceDoesNotRenotify() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        registry.setEnabled(false, for: RecordingPlugin.identifier)
        plugin.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertTrue(plugin.calls.isEmpty)
    }

    func testAPluginThatDoesNotImplementTheHookStillWorks() {
        // The default implementation must make this a no-op, not a crash.
        let plugin = SilentPlugin(context: context(SilentPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin], defaults: makeDefaults())

        registry.setEnabled(false, for: SilentPlugin.identifier)

        XCTAssertFalse(registry.isEnabled(SilentPlugin.identifier))
    }
}

/// Implements none of the optional protocol members.
@MainActor
@Observable
private final class SilentPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.silent"
    static let displayName = "Silent"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }
}
