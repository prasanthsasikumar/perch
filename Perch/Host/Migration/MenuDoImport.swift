import Foundation
import MenuDoPlugin

/// The manual "Import from MenuDo…" action, minus the file picker.
///
/// Split out of `GeneralSettingsView` because the copy and the plugin's reload
/// are one invariant, not two steps: a copy without the reload is precisely the
/// bug that destroyed the user's imported tasks. Left inside a view method that
/// line was untestable, and deleting it broke nothing. Here it is pinned.
///
/// The view keeps what only a view can do — running the `NSOpenPanel` and
/// rendering the result.
@MainActor
enum MenuDoImport {
    /// What to tell the user, in the window they are actually looking at.
    struct Feedback: Equatable {
        var message: String
        var isFailure: Bool
    }

    /// Copies `source` into MenuDo's storage and, on success, tells the running
    /// plugin to re-read it.
    ///
    /// The reload happens in the same synchronous main-actor turn as the copy.
    /// The plugin is live and holding the empty list it loaded at launch; the
    /// next save — a quit, an added task — would write that list straight back
    /// over the file just imported. Nothing suspends in between, so there is no
    /// window in which the host has changed a plugin's file behind its back.
    @discardableResult
    static func perform(
        from source: URL,
        registry: PluginRegistry,
        migration: MigrationState,
        // Resolved in the body rather than as a default argument: default
        // argument expressions are evaluated nonisolated, and the real
        // destination is main-actor-isolated. `nil` means "the real one".
        destination: URL? = nil
    ) -> Feedback {
        let destination = destination ?? LegacyImporter.menuDoTasksDestination
        let outcome = LegacyImporter.importTasksOutcome(from: source, to: destination)

        if outcome == .imported {
            registry.reload(id: MenuDo.identifier)
        }

        switch outcome {
        case .imported:
            migration.notice = MigrationState.importedNotice
            return Feedback(message: "Imported — your tasks are in Perch now.", isFailure: false)
        case .alreadyHasData:
            return Feedback(
                message: "Nothing imported — Perch already has tasks saved.", isFailure: false
            )
        case .nothingToImport:
            return Feedback(
                message: "That file is no longer there — choose the tasks.json file again.",
                isFailure: true
            )
        case .failed:
            return Feedback(
                message: "Import failed — something went wrong copying that file. "
                    + "Check that Perch can read it and try again.",
                isFailure: true
            )
        }
    }
}
