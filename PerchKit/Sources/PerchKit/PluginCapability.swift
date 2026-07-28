import Foundation

/// What a plugin does that a user would want disclosed before enabling it.
///
/// This describes behaviour, not enforcement. macOS entitlements are per-app,
/// not per-plugin, so once any plugin declares `.network` the whole binary
/// carries the network entitlement. Perch's Settings pane says what each
/// plugin does; it cannot sandbox one plugin away from another's permissions.
public enum PluginCapability: String, CaseIterable, Sendable {
    case credentials
    case network
    case notifications

    public var disclosure: String {
        switch self {
        case .credentials: "Stores an account credential"
        case .network: "Connects to the internet"
        case .notifications: "Sends notifications"
        }
    }
}

public extension Set where Element == PluginCapability {
    /// Human-readable disclosure lines, in a stable order. A plugin that
    /// declares nothing gets an explicit reassurance rather than blank space.
    var disclosureLines: [String] {
        guard !isEmpty else { return ["Stays entirely on your Mac"] }
        return PluginCapability.allCases.filter(contains).map(\.disclosure)
    }
}
