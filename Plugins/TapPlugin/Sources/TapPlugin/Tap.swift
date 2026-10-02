import Observation
import PerchKit
import SwiftUI
import TapKit

/// Knock the MacBook, run a shortcut: one, two or three knocks on the
/// chassis or the desk, read from the built-in motion sensor. A port of
/// MacTap (MIT, Jaskirat Singh).
///
/// The sensor, the classifier and the actions run in PerchTap, an
/// unsandboxed companion inside Perch.app, for reasons `TapLink` gives.
/// This plugin is its interface: the settings, the live view, and the
/// switch that starts and stops it.
@MainActor
@Observable
public final class Tap: PerchPlugin {
    public static let identifier = TapLink.pluginIdentifier
    public static let displayName = "Tap"
    public static let icon = "hand.tap"
    public static let capabilities: Set<PluginCapability> = [.accessibility]

    public let store: TapStore

    public required convenience init(context: PluginContext) {
        self.init(context: context, link: LiveCompanionLink())
    }

    /// The testable initializer.
    public init(context: PluginContext, link: CompanionLink) {
        store = TapStore(storage: context.storage, link: link)
    }

    public var panel: AnyView {
        AnyView(TapPanelView(store: store))
    }

    public var settings: AnyView {
        AnyView(TapSettingsView(store: store))
    }

    /// The same three states MacTap shows: listening, paused, and a Mac
    /// without a sensor to listen to.
    public var menuBarLabel: MenuBarLabel? {
        guard store.status != nil else { return MenuBarLabel(systemImage: Self.icon) }
        if !store.isSensorAvailable { return MenuBarLabel(systemImage: "exclamationmark.triangle") }
        return MenuBarLabel(systemImage: store.isListening ? "hand.tap.fill" : "hand.tap")
    }

    public func flush() { store.saveNow() }

    /// The companion runs exactly while the plugin is on.
    public func setEnabled(_ isEnabled: Bool) {
        store.setEnabled(isEnabled)
    }
}
