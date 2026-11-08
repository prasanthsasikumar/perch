import Observation
import PerchKit
import ScrollKit
import SwiftUI

/// Reverse the mouse wheel while the trackpad stays natural, or any mix of
/// the two, per axis. What Scroll Reverser does, without a second app to keep.
///
/// macOS has one natural-scrolling switch for every device. Changing the
/// direction per device means rewriting scroll events as they arrive, which
/// takes an event tap the sandbox refuses, so the tap runs in PerchScroll,
/// an unsandboxed companion inside Perch.app (`ScrollLink` has the details).
/// This plugin is its interface: the settings, the status, and the switch
/// that starts and stops it.
@MainActor
@Observable
public final class Scroll: PerchPlugin {
    public static let identifier = ScrollLink.pluginIdentifier
    public static let displayName = "Scroll"
    public static let icon = "computermouse"
    public static let summary = "Reverse the mouse wheel while the trackpad stays natural."
    public static let capabilities: Set<PluginCapability> = [.input]

    public let store: ScrollStore

    public required convenience init(context: PluginContext) {
        self.init(context: context, link: LiveScrollCompanionLink())
    }

    /// The testable initializer.
    public init(context: PluginContext, link: ScrollCompanionLink) {
        store = ScrollStore(storage: context.storage, link: link)
    }

    public var panel: AnyView {
        AnyView(ScrollPanelView(store: store))
    }

    public var settings: AnyView {
        AnyView(ScrollSettingsView(store: store))
    }

    /// Filled while scrolls are being reversed, outlined otherwise.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: store.state == .active ? "computermouse.fill" : Self.icon)
    }

    public func flush() { store.saveNow() }

    /// The companion runs only while the plugin is on.
    public func setEnabled(_ isEnabled: Bool) {
        store.setEnabled(isEnabled)
    }
}
