import Observation

/// A one-off message shown at the top of the panel after a migration.
///
/// Deliberately not persisted: it is worth saying once, and a notice that
/// survives a relaunch becomes clutter.
@MainActor
@Observable
final class MigrationState {
    var notice: String?

    static let importedNotice =
        "Imported your tasks from MenuDo. You can move MenuDo.app to the Trash."

    func dismiss() { notice = nil }
}
