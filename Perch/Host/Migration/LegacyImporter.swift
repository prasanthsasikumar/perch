import Foundation
import MenuDoPlugin
import PerchKit

/// Carries a MenuDo 1.x user's data across the bundle identifier change.
///
/// Renaming the app moved the sandbox container, which took both the task file
/// and every `UserDefaults` value with it. This runs once, copies both, and
/// then never touches the old container again.
///
/// This is the one host type that is allowed to name `MenuDo` outside
/// `PerchApp`: it exists solely to move MenuDo 1.x's data, so pretending to be
/// plugin-agnostic would be a fiction. It names the plugin type rather than
/// repeating its identifier as a string, so the destination can never drift
/// from where the plugin actually reads.
enum LegacyImporter {
    struct Result: Equatable {
        var taskOutcome: TaskImportOutcome = .nothingToImport
        var importedPreferences = false

        /// Derived, not stored — one source of truth for what happened.
        var importedTasks: Bool { taskOutcome == .imported }
    }

    private static let hasRunKey = "legacyImportCompleted"

    /// The real home directory. `NSHomeDirectory()` is the sandbox container,
    /// so it cannot be used to find another app's container.
    private static var realHomeDirectory: URL {
        guard let entry = getpwuid(getuid()) else { return URL(fileURLWithPath: NSHomeDirectory()) }
        return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir))
    }

    private static var legacyContainer: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Containers/org.ahlab.MenuDo/Data", isDirectory: true)
    }

    static var legacyTasksURL: URL {
        legacyContainer
            .appendingPathComponent("Library/Application Support/MenuDo/tasks.json")
    }

    static var legacyPreferencesURL: URL {
        legacyContainer
            .appendingPathComponent("Library/Preferences/org.ahlab.MenuDo.plist")
    }

    /// Preference keys to carry over, old key to new key. The hotkey key is
    /// renamed because the shortcut itself was renamed to `openPerch`.
    private static let preferenceKeys = [
        "showTitleInMenuBar": "showTitleInMenuBar",
        "titleTruncationLength": "titleTruncationLength",
        "KeyboardShortcuts_openMenuDo": "KeyboardShortcuts_openPerch",
    ]

    /// Where an imported task file has to land: the exact URL `MenuDo`'s own
    /// storage reads from. Both the automatic import and the Settings button
    /// go through here, so the two can never target different files.
    ///
    /// `@MainActor` only because `MenuDo`'s metadata is — reading a plugin's
    /// identifier is main-actor work under the plugin protocol's isolation.
    @MainActor
    static var menuDoTasksDestination: URL {
        PluginContext.perch(MenuDo.identifier).storage.url(named: MenuDo.tasksFilename)
    }

    @MainActor
    @discardableResult
    static func runIfNeeded() -> Result {
        run(
            tasksSource: legacyTasksURL,
            tasksDestination: menuDoTasksDestination,
            preferencesSource: legacyPreferencesURL,
            defaults: .standard
        )
    }

    /// A transient failure (disk full, permissions, source vanishing mid-copy)
    /// must not be confused with there being nothing to import, or with the
    /// destination legitimately already holding data — only the former should
    /// leave `hasRunKey` unset so the next launch retries.
    ///
    /// Not `private`: the Settings import button needs this exact
    /// vocabulary to tell a genuine failure apart from "nothing to do," rather
    /// than collapsing every non-import outcome into one misleading message.
    enum TaskImportOutcome {
        case imported
        case nothingToImport
        case alreadyHasData
        case failed
    }

    static func run(
        tasksSource: URL,
        tasksDestination: URL,
        preferencesSource: URL,
        defaults: UserDefaults
    ) -> Result {
        guard !defaults.bool(forKey: hasRunKey) else { return Result() }

        var result = Result()
        result.taskOutcome = importTasksOutcome(from: tasksSource, to: tasksDestination)
        result.importedPreferences = importPreferences(from: preferencesSource, into: defaults)

        // A genuine failure — including a source we were refused — must be
        // retried on the next launch. Every other outcome (nothing to import,
        // or the destination already has data) is a permanent completion.
        if result.taskOutcome != .failed {
            defaults.set(true, forKey: hasRunKey)
        }
        return result
    }

    /// Whether a source file is there and actually readable.
    ///
    /// `FileManager.fileExists` collapses "no such file" and "the sandbox said
    /// no" into the same `false`, and only the first is a permanent, legitimate
    /// "nothing to import". Treating a denial as nothing-to-import sets
    /// `hasRunKey` forever, so a user whose read is refused once never gets
    /// another automatic attempt. The entitlement that makes this work today is
    /// not insurance against a future macOS, a notarized build, or a TCC
    /// change, so the two cases are told apart at the syscall level.
    enum SourceState: Equatable {
        case present
        case absent
        case unreadable
    }

    static func sourceState(of url: URL) -> SourceState {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            // Anything other than "it isn't there" — EACCES, EPERM, a sandbox
            // denial — is a refusal, not an absence.
            return errno == ENOENT ? .absent : .unreadable
        }
        // Metadata can be visible while the bytes are not, so ask separately.
        return access(url.path, R_OK) == 0 ? .present : .unreadable
    }

    /// Whether the destination holds tasks worth protecting.
    ///
    /// Existence is the wrong question. A plugin that saves an empty list —
    /// which every fresh Perch does the first time it quits, since `flush()`
    /// writes unconditionally — leaves a file at this exact path. Reading that
    /// as "already has data" retires the automatic retry the moment it becomes
    /// needed, and turns the Settings import button into a no-op for anyone
    /// who has ever launched and quit. So the file has to be opened.
    ///
    /// Anything that will not parse as an empty array counts as data. It might
    /// be a corrupt task list, and destroying one to complete a migration is
    /// the exact failure this importer exists to avoid — when in doubt, refuse.
    static func destinationHoldsData(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url) else { return true }
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return true
        }
        return !array.isEmpty
    }

    /// Copies rather than moves, and refuses to touch a destination that
    /// already holds data — losing tasks to a migration would be unforgivable.
    ///
    /// The Settings import button calls this directly, deliberately bypassing
    /// `hasRunKey`. It returns the full outcome rather than a collapsed `Bool`
    /// so the caller can show an honest, distinct message for each of
    /// "imported," "nothing to import," "already has data," and a genuine
    /// failure — the last of which must never be reported as if the user's
    /// data were safe.
    static func importTasksOutcome(from source: URL, to destination: URL) -> TaskImportOutcome {
        let fileManager = FileManager.default
        switch sourceState(of: source) {
        case .absent: return .nothingToImport
        // Retried next launch rather than written off as nothing to import.
        case .unreadable: return .failed
        case .present: break
        }
        guard !destinationHoldsData(at: destination) else { return .alreadyHasData }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Only an empty list can be sitting here — anything else was turned
            // away above — and `copyItem` refuses an existing destination.
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            return .imported
        } catch {
            return .failed
        }
    }

    private static func importPreferences(from source: URL, into defaults: UserDefaults) -> Bool {
        guard let plist = NSDictionary(contentsOf: source) as? [String: Any] else { return false }
        for (oldKey, newKey) in preferenceKeys {
            guard let value = plist[oldKey] else { continue }
            // Anything the user already set in Perch wins over the old value.
            guard defaults.object(forKey: newKey) == nil else { continue }
            defaults.set(value, forKey: newKey)
        }
        return true
    }
}
