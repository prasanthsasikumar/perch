import Foundation

/// Carries a plugin's stored data across a change of identifier.
///
/// An identifier names a plugin's storage directory and prefixes its
/// settings, and the registry remembers plugins by it. Change it without
/// this and the plugin comes up empty, re-enabled, and no longer primary.
struct PluginIdentifierMigration {
    let from: String
    let to: String

    /// The Tasks plugin used to go by the app's first name. The old
    /// identifier is spelled in pieces so that name appears nowhere.
    static let tasks = PluginIdentifierMigration(
        from: "org.ahlab.perch." + ["menu", "do"].joined(),
        to: "org.ahlab.perch.tasks"
    )

    /// Safe to run at every launch: once done, there is nothing left to do.
    func run(pluginsDirectory: URL, defaults: UserDefaults, fileManager: FileManager = .default) {
        moveStorage(in: pluginsDirectory, fileManager: fileManager)
        renameInRegistry(defaults)
        moveSettings(defaults)
    }

    /// Anything already under the new identifier is newer, so it wins and
    /// the old directory is left alone rather than deleted.
    private func moveStorage(in pluginsDirectory: URL, fileManager: FileManager) {
        let old = pluginsDirectory.appendingPathComponent(from, isDirectory: true)
        let new = pluginsDirectory.appendingPathComponent(to, isDirectory: true)
        guard fileManager.fileExists(atPath: old.path),
              !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }

    private func renameInRegistry(_ defaults: UserDefaults) {
        for key in ["enabledPluginIDs", "seenPluginIDs"] {
            guard let ids = defaults.stringArray(forKey: key), ids.contains(from) else { continue }
            defaults.set(ids.map { $0 == from ? to : $0 }, forKey: key)
        }
        for key in ["activePluginID", "primaryPluginID"] where defaults.string(forKey: key) == from {
            defaults.set(to, forKey: key)
        }
    }

    private func moveSettings(_ defaults: UserDefaults) {
        let prefix = from + "."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let moved = to + "." + key.dropFirst(prefix.count)
            if defaults.object(forKey: moved) == nil {
                defaults.set(value, forKey: moved)
            }
            defaults.removeObject(forKey: key)
        }
    }
}
