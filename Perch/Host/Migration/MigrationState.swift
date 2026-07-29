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

    /// The automatic import couldn't read or copy the old file. Silence here
    /// leaves a MenuDo 1.x user staring at an empty list with no idea why, and
    /// no idea the manual fallback exists.
    static let importFailedNotice =
        "Couldn't bring your tasks over from MenuDo automatically. "
        + "Open Settings → General → Import from MenuDo to choose the file yourself."

    func dismiss() { notice = nil }
}
