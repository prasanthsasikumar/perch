import Foundation

public enum PluginStorageError: Error, Equatable {
    /// The file existed but could not be decoded. A `.bak` copy was kept beside it.
    case unreadable
}

/// A plugin's private corner of disk. Every plugin gets its own directory, so
/// two plugins can never collide on a filename.
///
/// Reads and writes are synchronous and small by design — a plugin's state is
/// expected to be a modest JSON document. Callers that mutate often should
/// debounce their own writes rather than expecting this type to.
public final class PluginStorage {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Returns `nil` when the file does not exist, which is the normal
    /// first-launch case rather than an error.
    ///
    /// A file that exists but cannot be decoded is copied to `<name>.bak`
    /// before throwing, so a decoding bug never silently destroys user data.
    public func load<T: Decodable>(_ type: T.Type, named name: String) throws -> T? {
        let fileURL = url(named: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: fileURL))
        } catch {
            let backupURL = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            throw PluginStorageError.unreadable
        }
    }

    public func save<T: Encodable>(_ value: T, named name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url(named: name), options: .atomic)
    }
}
