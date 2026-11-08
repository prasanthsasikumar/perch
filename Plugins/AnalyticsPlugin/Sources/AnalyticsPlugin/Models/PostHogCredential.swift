import Foundation

/// Everything needed to query one PostHog project.
///
/// Kept whole in the Keychain rather than split between the Keychain and the
/// plugin's cache: the region and project id are not secret, but they are
/// meaningless without the key, and keeping all three together means there is
/// never a half-configured state to explain.
public struct PostHogCredential: Codable, Equatable, Sendable {
    /// PostHog Cloud runs two separate regions, and a key from one is unknown
    /// to the other.
    public enum Region: String, Codable, CaseIterable, Identifiable, Sendable {
        case us
        case eu

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .us: "US Cloud"
            case .eu: "EU Cloud"
            }
        }

        /// The app host, not the ingestion host (`us.i.posthog.com`): the
        /// query API lives only on the former.
        public var host: URL {
            switch self {
            case .us: URL(string: "https://us.posthog.com")!
            case .eu: URL(string: "https://eu.posthog.com")!
            }
        }
    }

    public var region: Region
    /// The number in the project's URL and in Settings › Project › General.
    public var projectID: String
    /// A personal API key (`phx_…`), not the project's public `phc_` token:
    /// the public token can only send events, never read them.
    public var apiKey: String

    public init(region: Region, projectID: String, apiKey: String) {
        self.region = region
        self.projectID = projectID
        self.apiKey = apiKey
    }

    /// Validates what was typed into Settings. Trims first, because both
    /// values are normally pasted, and pasted text often carries a newline.
    public static func validated(region: Region, projectID rawProjectID: String, apiKey rawKey: String) throws -> PostHogCredential {
        let projectID = rawProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty, projectID.allSatisfy(\.isASCIIDigit) else {
            throw AnalyticsError.malformedKey("the project ID is a number, like 12345")
        }
        // The project token is the key people find first, because it is in
        // every snippet they pasted into their sites. Naming it saves a
        // confusing 401 later.
        if apiKey.hasPrefix("phc_") {
            throw AnalyticsError.malformedKey("that's the project token; a personal API key starts with phx_")
        }
        guard apiKey.hasPrefix("phx_"), apiKey.count > 8 else {
            throw AnalyticsError.malformedKey("a personal API key starts with phx_")
        }
        return PostHogCredential(region: region, projectID: projectID, apiKey: apiKey)
    }

    /// Enough of the key to recognise it in Settings, not enough to use it.
    public var maskedKey: String {
        "phx_…" + apiKey.suffix(4)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
