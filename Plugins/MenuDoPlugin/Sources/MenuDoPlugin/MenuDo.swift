import Observation
import PerchKit
import SwiftUI

/// The todo list Perch grew out of: your current task in the menu bar, and a
/// flat list one click away.
///
/// Declares no capabilities. Nothing it stores ever leaves the Mac.
@MainActor
@Observable
public final class MenuDo: PerchPlugin {
    public static let identifier = "org.ahlab.perch.menudo"
    public static let displayName = "Tasks"
    public static let icon = "checkmark.circle"
    public static let capabilities: Set<PluginCapability> = []

    /// The file `store` reads and writes inside the plugin's storage
    /// directory. Public because the host's legacy importer copies into
    /// exactly this file, and a guessed name would import into a file nothing
    /// ever loads.
    public static let tasksFilename = "tasks.json"

    public let store: TaskStore

    public required init(context: PluginContext) {
        store = TaskStore(storage: context.storage, filename: Self.tasksFilename)
    }

    public var panel: AnyView {
        AnyView(TaskListView(store: store))
    }

    /// Always contributes its icon, so the menu bar item keeps a stable
    /// appearance even with an empty list; the text is the current task.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: Self.icon, text: store.currentTask?.title)
    }

    /// The legacy import copies a tasks file straight into this plugin's
    /// storage while the store is already live and holding an empty list.
    /// Re-reading is what stops that empty list from being written back.
    public func reload() { store.reload() }

    /// The store debounces its writes, so there is routinely up to half a
    /// second of unsaved work when the user quits.
    public func flush() { store.saveNow() }

    public var footerActions: [PluginAction] {
        guard !store.done.isEmpty else { return [] }
        return [
            PluginAction(id: "clearCompleted", title: "Clear completed") { [store] in
                store.clearCompleted()
            }
        ]
    }
}
