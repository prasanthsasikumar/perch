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

    public let store: TaskStore

    public required init(context: PluginContext) {
        store = TaskStore(storage: context.storage)
    }

    public var panel: AnyView {
        AnyView(TaskListView(store: store))
    }

    /// Always contributes its icon, so the menu bar item keeps a stable
    /// appearance even with an empty list; the text is the current task.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: Self.icon, text: store.currentTask?.title)
    }

    public var footerActions: [PluginAction] {
        guard !store.done.isEmpty else { return [] }
        return [
            PluginAction(id: "clearCompleted", title: "Clear completed") { [store] in
                store.clearCompleted()
            }
        ]
    }
}
