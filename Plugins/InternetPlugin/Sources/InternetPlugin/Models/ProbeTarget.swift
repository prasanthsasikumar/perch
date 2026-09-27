import Foundation

/// Somewhere on the internet worth asking "are you there?".
///
/// Three targets rather than one, because each answers a different question:
/// Cloudflare is reached by IP, so it works even when DNS does not; Google is
/// reached by name; and Apple's page is the one macOS itself uses to spot a
/// captive portal, so a hotel login page shows up as that rather than as
/// "offline".
public struct ProbeTarget: Equatable, Sendable, Identifiable {
    /// What a healthy answer looks like. Anything else that still arrives is a
    /// captive portal (or a proxy) answering on the target's behalf.
    public enum Expectation: Equatable, Sendable {
        case status(Int)
        case bodyContains(String)
    }

    public let id: String
    public let name: String
    public let url: URL
    public let expectation: Expectation
    /// Whether reaching this target needs DNS. The one that does not is what
    /// lets the panel tell "DNS is broken" apart from "the internet is down".
    public let usesDNS: Bool

    public init(id: String, name: String, url: URL, expectation: Expectation, usesDNS: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.expectation = expectation
        self.usesDNS = usesDNS
    }

    public func accepts(status: Int, body: Data) -> Bool {
        switch expectation {
        case .status(let expected):
            return status == expected
        case .bodyContains(let needle):
            guard status == 200 else { return false }
            return String(decoding: body, as: UTF8.self).contains(needle)
        }
    }

    public static let defaults: [ProbeTarget] = [
        ProbeTarget(
            id: "cloudflare",
            name: "Cloudflare (1.1.1.1)",
            url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!,
            expectation: .bodyContains("h=1.1.1.1"),
            usesDNS: false
        ),
        ProbeTarget(
            id: "google",
            name: "Google",
            url: URL(string: "https://www.google.com/generate_204")!,
            expectation: .status(204),
            usesDNS: true
        ),
        ProbeTarget(
            id: "apple",
            name: "Apple",
            url: URL(string: "https://captive.apple.com/hotspot-detect.html")!,
            expectation: .bodyContains("Success"),
            usesDNS: true
        ),
    ]
}

/// How one probe went.
public enum ProbeOutcome: Codable, Equatable, Sendable {
    /// Answered correctly, this many milliseconds after asking.
    case ok(milliseconds: Double)
    /// Something answered, but not the target: a login page or a proxy.
    case intercepted
    /// The name would not resolve.
    case dnsFailed
    /// No answer at all: timed out, refused, or no route.
    case failed

    public var milliseconds: Double? {
        if case .ok(let ms) = self { return ms }
        return nil
    }

    public var isOK: Bool { milliseconds != nil }
}

/// One round of probes: every target, asked at the same moment.
public struct Check: Codable, Equatable, Sendable {
    public var at: Date
    /// Keyed by `ProbeTarget.id`.
    public var outcomes: [String: ProbeOutcome]

    public init(at: Date, outcomes: [String: ProbeOutcome]) {
        self.at = at
        self.outcomes = outcomes
    }

    /// The fastest answer, which is the closest thing to the line's own round
    /// trip: slower targets are slow for reasons of their own.
    public var latency: Double? {
        outcomes.values.compactMap(\.milliseconds).min()
    }

    public var failures: Int { outcomes.values.filter { !$0.isOK }.count }
    public var allFailed: Bool { !outcomes.isEmpty && failures == outcomes.count }
}

/// The last download speed test.
public struct SpeedResult: Codable, Equatable, Sendable {
    public var megabitsPerSecond: Double
    public var at: Date

    public init(megabitsPerSecond: Double, at: Date) {
        self.megabitsPerSecond = megabitsPerSecond
        self.at = at
    }
}
