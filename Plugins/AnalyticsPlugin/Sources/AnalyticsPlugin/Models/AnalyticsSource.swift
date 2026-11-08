import Foundation

/// Where the numbers come from. Each source keeps its own credential, its own
/// list of sites and its own cache, so switching back and forth is a change of
/// view rather than a reset.
public enum AnalyticsSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case googleAnalytics
    case postHog

    public var id: String { rawValue }

    /// The product's own name, for the picker and for error messages.
    public var title: String {
        switch self {
        case .googleAnalytics: "Google Analytics"
        case .postHog: "PostHog"
        }
    }

    /// What one watched thing is called. GA has properties; a PostHog project
    /// is one bucket that many websites share, told apart by domain.
    public var siteNoun: String {
        switch self {
        case .googleAnalytics: "property"
        case .postHog: "site"
        }
    }

    /// The `PluginDefaults` key the choice is kept under.
    static let defaultsKey = "source"
}
