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

        // Cleartext http to a public host is upgraded to https rather than
        // stored as typed. Two reasons, either of which is sufficient: App
        // Transport Security refuses the request outright, so it could only
        // ever fail; and this endpoint carries a basic-auth password, which has
        // no business travelling in clear. Loopback and LAN names keep http,
        // because that is how the agent is legitimately reached over an SSH
        // tunnel or inside a home network, and ATS permits it there.
        if scheme == "http", !Self.isLocal(host) {
            components.scheme = "https"
        }

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

    /// Hosts where cleartext http is legitimate and ATS allows it.
    static func isLocal(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name == "127.0.0.1" || name == "::1" { return true }
        if name.hasSuffix(".local") || name.hasSuffix(".localhost") { return true }
        // RFC1918 private ranges.
        if name.hasPrefix("10.") || name.hasPrefix("192.168.") { return true }
        if name.hasPrefix("172.") {
            let parts = name.split(separator: ".")
            if parts.count == 4, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
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
