import Foundation
import PerchKit

/// Carries a MenuDo 1.x user's data across the bundle identifier change.
///
/// Renaming the app moved the sandbox container, which took both the task file
/// and every `UserDefaults` value with it. This runs once, copies both, and
/// then never touches the old container again.
enum LegacyImporter {
    struct Result: Equatable {
        var importedTasks = false
        var importedPreferences = false
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

    @discardableResult
    static func runIfNeeded() -> Result {
        run(
            tasksSource: legacyTasksURL,
            tasksDestination: PluginContext
                .standard(appName: "Perch", identifier: "org.ahlab.perch.menudo")
                .storage
                .url(named: "tasks.json"),
            preferencesSource: legacyPreferencesURL,
            defaults: .standard
        )
    }

    static func run(
        tasksSource: URL,
        tasksDestination: URL,
        preferencesSource: URL,
        defaults: UserDefaults
    ) -> Result {
        guard !defaults.bool(forKey: hasRunKey) else { return Result() }
        defer { defaults.set(true, forKey: hasRunKey) }

        var result = Result()
        result.importedTasks = importTasks(from: tasksSource, to: tasksDestination)
        result.importedPreferences = importPreferences(from: preferencesSource, into: defaults)
        return result
    }

    /// Copies rather than moves, and refuses to touch a destination that
    /// already holds data — losing tasks to a migration would be unforgivable.
    static func importTasks(from source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return false }
        guard !fileManager.fileExists(atPath: destination.path) else { return false }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
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
