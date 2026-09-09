import Foundation

/// Turns whatever the user typed into the URL the agent actually serves.
///
/// People paste three things: the dashboard root, the root with a trailing
/// slash, and occasionally the JSON endpoint itself. All three should work,
/// and a bare hostname should too, so `https://` is assumed rather than
/// demanded.
public enum EndpointURL {
    public static let path = "/api/now"

    public static func normalise(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        // Credentials pasted into the URL are dropped: the password belongs in
        // the Keychain, and leaving it here would write it to disk in plain
        // JSON with the rest of the target.
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(Self.path) {
            path += Self.path
        }
        components.path = path

        return components.url
    }

    /// The address to show the user and to open in a browser: the same host,
    /// without the API path.
    public static func dashboardURL(for endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { return endpoint }
        var path = components.path
        if path.hasSuffix(Self.path) {
            path.removeLast(Self.path.count)
        }
        components.path = path
        return components.url ?? endpoint
    }
}
