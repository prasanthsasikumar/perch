import Foundation

/// Everything the host hands a plugin at construction. A plugin should reach
/// for the world only through this — that is what keeps plugins testable and
/// keeps the host free to change where things live on disk.
public struct PluginContext {
    public let storage: PluginStorage
    public let defaults: PluginDefaults

    public init(storage: PluginStorage, defaults: PluginDefaults) {
        self.storage = storage
        self.defaults = defaults
    }

    /// The standard on-disk layout:
    /// `Application Support/<appName>/Plugins/<identifier>/`
    public static func standard(appName: String, identifier: String) -> PluginContext {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        return PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(prefix: identifier)
        )
    }
}
