import Observation
import SwiftUI

/// A tool that lives inside Perch.
///
/// `AnyView` rather than associated types is deliberate. Associated types make
/// `[any PerchPlugin]` painful to hold and iterate, and a menu bar panel is
/// nowhere near the performance envelope where erasure costs anything.
///
/// `Observable` is required rather than merely encouraged: the host reads
/// `menuBarLabel` and `footerActions` during view evaluation, so a plugin whose
/// state changes must be observable for the menu bar to update.
///
/// This API is 0.x and unstable. It will change once a second plugin exists to
/// prove the shape is right.
@MainActor
public protocol PerchPlugin: AnyObject, Observable {
    /// Reverse-DNS, e.g. `"org.ahlab.perch.menudo"`. Also names this plugin's
    /// storage directory and its `UserDefaults` prefix, so it must be stable
    /// across releases — changing it orphans the user's data.
    static var identifier: String { get }
    /// Shown on the panel's tab and in Settings.
    static var displayName: String { get }
    /// SF Symbol name.
    static var icon: String { get }
    /// Disclosed to the user in Settings before they enable the plugin.
    static var capabilities: Set<PluginCapability> { get }

    init(context: PluginContext)

    /// Everything between the tab strip and the footer.
    var panel: AnyView { get }
    /// This plugin's pane in the Settings window. Default: nothing.
    var settings: AnyView { get }
    /// What to show in the menu bar when this plugin is primary. Default: nothing.
    var menuBarLabel: MenuBarLabel? { get }
    /// Buttons contributed to the left of the panel footer. Default: none.
    var footerActions: [PluginAction] { get }
}

public extension PerchPlugin {
    var settings: AnyView { AnyView(EmptyView()) }
    var menuBarLabel: MenuBarLabel? { nil }
    var footerActions: [PluginAction] { [] }

    // Instance mirrors of the statics, so the host can read metadata off an
    // `any PerchPlugin` without opening the existential.
    var identifier: String { Self.identifier }
    var displayName: String { Self.displayName }
    var icon: String { Self.icon }
    var capabilities: Set<PluginCapability> { Self.capabilities }
}
