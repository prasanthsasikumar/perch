import Observation
import PerchKit
import SwiftUI

/// Facebook Marketplace searches in the menu bar: type a query and a price
/// cap, and new listings turn up in the panel.
///
/// Declares `.network` because it talks to Facebook, and `.notifications`
/// because it tells you when something turns up.
@MainActor
@Observable
public final class Market: PerchPlugin {
    public static let identifier = "org.ahlab.perch.market"
    public static let displayName = "Market"
    public static let icon = "binoculars"
    public static let capabilities: Set<PluginCapability> = [.network, .notifications]

    public let store: MarketStore
    public let poller: WatchPoller

    public required convenience init(context: PluginContext) {
        self.init(context: context, source: StubListingSource())
    }

    /// The testable initializer. Plan 2 passes the real WKWebView-backed
    /// source here; tests pass a fake.
    public init(context: PluginContext, source: ListingSource) {
        let store = MarketStore(storage: context.storage)
        self.store = store
        poller = WatchPoller(store: store, source: source)
    }

    public var panel: AnyView {
        AnyView(MarketPanelView(store: store, poller: poller))
    }

    public var settings: AnyView {
        AnyView(MarketSettingsView(store: store))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape,
    /// with the count appearing once there is one.
    public var menuBarLabel: MenuBarLabel? {
        let unseen = store.totalUnseen
        return MenuBarLabel(systemImage: Self.icon, text: unseen > 0 ? "\(unseen)" : nil)
    }

    /// The store debounces its writes; this covers the window between a poll
    /// landing and the process dying.
    public func flush() { store.saveNow() }

    /// The host calls this at startup with the stored state, and again on
    /// every toggle. Polling Facebook is precisely the kind of work a user
    /// expects to stop when they switch a plugin off.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            poller.run()
        } else {
            poller.stop()
        }
    }
}
