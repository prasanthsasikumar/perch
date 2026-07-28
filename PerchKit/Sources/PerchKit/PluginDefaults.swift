import Foundation

/// A plugin's slice of `UserDefaults`. Every key is prefixed with the plugin
/// identifier, so two plugins asking for `"interval"` get two different values.
public final class PluginDefaults {
    private let suite: UserDefaults
    private let prefix: String

    public init(suite: UserDefaults = .standard, prefix: String) {
        self.suite = suite
        self.prefix = prefix
    }

    private func key(_ name: String) -> String { "\(prefix).\(name)" }

    public func bool(_ name: String, default fallback: Bool) -> Bool {
        suite.object(forKey: key(name)) as? Bool ?? fallback
    }

    public func integer(_ name: String, default fallback: Int) -> Int {
        suite.object(forKey: key(name)) as? Int ?? fallback
    }

    public func string(_ name: String) -> String? {
        suite.string(forKey: key(name))
    }

    public func set(_ value: Bool, for name: String) {
        suite.set(value, forKey: key(name))
    }

    public func set(_ value: Int, for name: String) {
        suite.set(value, forKey: key(name))
    }

    public func set(_ value: String?, for name: String) {
        if let value {
            suite.set(value, forKey: key(name))
        } else {
            suite.removeObject(forKey: key(name))
        }
    }
}
