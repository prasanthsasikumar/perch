import Foundation

/// Pulls links out of whatever was pasted: one URL, several separated by
/// spaces or newlines, or a URL with the scheme left off.
public enum PastedLinks {
    public static func extract(_ text: String) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            guard let url = url(from: String(token)) else { continue }
            if seen.insert(url.absoluteString).inserted { urls.append(url) }
        }
        return urls
    }

    private static func url(from token: String) -> URL? {
        let lowered = token.lowercased()
        let candidate: String
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            candidate = token
        } else if !token.contains("://"), token.contains(".") {
            candidate = "https://" + token
        } else {
            return nil
        }
        guard let url = URL(string: candidate), let host = url.host(), host.contains(".") else {
            return nil
        }
        return url
    }
}
