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
        static let active = "activePluginID"
        static let primary = "primaryPluginID"
    }

    let entries: [Entry]
    private let defaults: UserDefaults

    private var enabledIDs: Set<String> {
        didSet {
            persistEnabledIDs()
            reconcileSelections()
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
        // A plugin removed from a build leaves its id behind in defaults;
        // filtering against `known` keeps those ghosts out of the UI.
        if let stored = defaults.array(forKey: Key.enabled) as? [String] {
            enabledIDs = Set(stored).intersection(known)
        } else {
            enabledIDs = known
        }
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

    /// Tells one plugin its storage changed underneath it. Like `flushAll`,
    /// this reaches a disabled plugin — the legacy import can land on one the
    /// user happens to have switched off, and it must not read stale state if
    /// they switch it back on.
    func reload(id: String) {
        entries.first { $0.id == id }?.plugin.reload()
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
