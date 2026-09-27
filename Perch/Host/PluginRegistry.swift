import Foundation
import Observation
import PerchKit

/// The one host type that knows which plugins exist.
///
/// Everything else in the host works off `Entry`, so adding a plugin means
/// touching exactly one array in `PerchApp` and nothing else.
@MainActor
@Observable
final class PluginRegistry {
    /// A plugin plus the metadata the host needs to draw it. Metadata is
    /// copied at construction so list rendering never reaches into the plugin.
    struct Entry: Identifiable {
        let id: String
        let plugin: any PerchPlugin
        let displayName: String
        let icon: String
        let capabilities: Set<PluginCapability>
    }

    private enum Key {
        static let enabled = "enabledPluginIDs"
        static let seen = "seenPluginIDs"
        static let active = "activePluginID"
        static let primary = "primaryPluginID"
    }

    let entries: [Entry]
    private let defaults: UserDefaults

    private var enabledIDs: Set<String> {
        didSet {
            persistEnabledIDs()
            // Selections are settled before plugins are notified, so a
            // plugin's `setEnabled` never sees `activeID` still naming a
            // plugin that was just switched off.
            reconcileSelections()
            notifyEnabledChanges(from: oldValue)
        }
    }

    var activeID: String? {
        didSet { defaults.set(activeID, forKey: Key.active) }
    }

    var primaryID: String? {
        didSet { defaults.set(primaryID, forKey: Key.primary) }
    }

    init(plugins: [any PerchPlugin], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = plugins.map { plugin in
            Entry(
                id: plugin.identifier,
                plugin: plugin,
                displayName: plugin.displayName,
                icon: plugin.icon,
                capabilities: plugin.capabilities
            )
        }

        let known = Set(entries.map(\.id))
        let stored = defaults.array(forKey: Key.enabled) as? [String]
        // Which plugins this install has ever been offered. Without it, a
        // plugin added in a later release would be absent from the stored
        // enabled list and so arrive switched off — indistinguishable, to the
        // code, from one the user turned off on purpose. Upgraders would never
        // see it. Falling back to the stored enabled list seeds this for
        // installs that predate the key, so a plugin deliberately switched off
        // before the upgrade stays off.
        let seen = Set(defaults.array(forKey: Key.seen) as? [String] ?? stored ?? [])

        if let stored {
            // A plugin removed from a build leaves its id behind in defaults;
            // intersecting with `known` keeps those ghosts out of the UI.
            enabledIDs = Set(stored).intersection(known).union(known.subtracting(seen))
        } else {
            enabledIDs = known
        }
        defaults.set(Array(known), forKey: Key.seen)
        activeID = defaults.string(forKey: Key.active).flatMap { known.contains($0) ? $0 : nil }
        primaryID = defaults.string(forKey: Key.primary).flatMap { known.contains($0) ? $0 : nil }

        // Swift suppresses `didSet` for the assignments directly above, since
        // they're written in this initializer's own body — so, unlike
        // `activeID`/`primaryID` below (which get reassigned from inside
        // `reconcileSelections`, a genuine method call, and so persist via
        // their own `didSet`), `enabledIDs` needs an explicit write here to
        // keep all three defaults keys populated after a fresh install.
        persistEnabledIDs()
        reconcileSelections()
        notifyInitialEnabledState()
    }

    // MARK: - Derived state

    var enabled: [Entry] {
        entries.filter { enabledIDs.contains($0.id) }
    }

    var active: Entry? {
        enabled.first { $0.id == activeID } ?? enabled.first
    }

    var primary: Entry? {
        enabled.first { $0.id == primaryID } ?? enabled.first
    }

    /// With a single plugin the panel should look exactly like that plugin's
    /// own window — no chrome advertising a framework the user didn't ask for.
    var showsTabStrip: Bool { enabled.count > 1 }

    /// Past five, named tabs no longer fit across the 320-point panel and the
    /// strip clips; each plugin's icon stands in for its name instead. Five or
    /// fewer keep their names, which are easier to read than icons.
    var tabStripUsesIcons: Bool { Self.tabsUseIcons(count: enabled.count) }

    static let maxNamedTabs = 5

    static func tabsUseIcons(count: Int) -> Bool { count > maxNamedTabs }

    // MARK: - Mutation

    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    func setEnabled(_ isEnabled: Bool, for id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if isEnabled {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
    }

    /// Makes `PerchPlugin.flush()`'s promise real: called from the panel's Quit
    /// button and from `NSApplication.willTerminateNotification`, so a plugin
    /// with debounced writes never has to hook the app lifecycle itself.
    ///
    /// Every entry, not just the enabled ones. Disabling a plugin hides it; it
    /// does not destroy it, and it does not discard whatever the user typed
    /// just before they switched it off. `flush()` means "the process is about
    /// to die, write now" — that is true of a plugin regardless of whether its
    /// tab is currently on screen.
    func flushAll() {
        for entry in entries { entry.plugin.flush() }
    }

    /// Tells each plugin whose state actually changed, and no others.
    ///
    /// Only the changed ones: re-notifying everything on every toggle would
    /// require every `setEnabled` implementation to be idempotent for no gain.
    private func notifyEnabledChanges(from oldValue: Set<String>) {
        for entry in entries where enabledIDs.contains(entry.id) != oldValue.contains(entry.id) {
            entry.plugin.setEnabled(enabledIDs.contains(entry.id))
        }
    }

    /// Every plugin learns its stored state once, at startup, before it has a
    /// chance to start any background work of its own.
    private func notifyInitialEnabledState() {
        for entry in entries { entry.plugin.setEnabled(enabledIDs.contains(entry.id)) }
    }

    private func persistEnabledIDs() {
        defaults.set(Array(enabledIDs), forKey: Key.enabled)
    }

    /// Keeps the stored selections pointing at something real, so a disabled
    /// plugin never leaves the panel blank or the menu bar stuck on stale text.
    private func reconcileSelections() {
        let fallback = enabled.first?.id
        if activeID == nil || !enabledIDs.contains(activeID!) { activeID = fallback }
        if primaryID == nil || !enabledIDs.contains(primaryID!) { primaryID = fallback }
    }
}
