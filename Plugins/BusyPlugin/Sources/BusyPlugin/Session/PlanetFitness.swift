import Foundation

/// Planet Fitness clubs publish a live Crowd Meter on their public page
/// (planetfitness.com/gyms/<club>): percent of capacity, the headcount, and
/// an hour-by-hour history. Verified against real club pages on 2026-10-05.
public enum PlanetFitness {
    /// What a fresh install starts with.
    public static let sampleClub = "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa"

    /// The meter is ten bars of 10% capacity. One bar means no waits and
    /// three mean lines, so the wording turns over at one and two bars; the
    /// phrases are the ones `BusyLevel` already reads from Google.
    public static func wording(percent: Int) -> String {
        if percent <= 10 { return "Not too busy" }
        if percent <= 20 { return "A little busy" }
        return "Busy"
    }
}

/// The club page for a pasted link, or nil when the query isn't one.
///
/// Accepts the link with or without scheme or `www`, a trailing slash, a
/// sub-page such as `/offers`, a query string, and any capitalisation.
public func planetFitnessClubURL(query: String) -> URL? {
    var text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !text.contains("://") { text = "https://" + text }
    guard let components = URLComponents(string: text),
          let host = components.host, host == "planetfitness.com" || host == "www.planetfitness.com"
    else { return nil }
    let parts = components.path.split(separator: "/")
    guard parts.count >= 2, parts[0] == "gyms",
          parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
    else { return nil }
    return URL(string: "https://www.planetfitness.com/gyms/\(parts[1])")
}

/// Reads a Planet Fitness club page through the same hidden webview as Google.
@MainActor
public struct PlanetFitnessBusynessSource: BusynessSource {
    private let session: GoogleSession

    public init(session: GoogleSession) {
        self.session = session
    }

    public func fetch(query: String) async throws -> BusyReading {
        guard let url = planetFitnessClubURL(query: query) else {
            throw BusyError.failed("this isn't a Planet Fitness club link")
        }
        return try Self.judge(try await session.load(url: url, script: "planetfitness"))
    }

    /// Pure: the script reports, this decides.
    static func judge(_ page: LoadedPage) throws -> BusyReading {
        let extracted = try decodeExtractedPage(page.payload)
        guard extracted.found, let percent = extracted.reading.livePercent else { throw BusyError.noCrowdMeter }
        var reading = extracted.reading
        reading.statusText = PlanetFitness.wording(percent: percent)
        return reading
    }
}

/// Sends club links to Planet Fitness and everything else to Google.
@MainActor
public struct RoutingBusynessSource: BusynessSource {
    let google: BusynessSource
    let planetFitness: BusynessSource

    public init(google: BusynessSource, planetFitness: BusynessSource) {
        self.google = google
        self.planetFitness = planetFitness
    }

    public func fetch(query: String) async throws -> BusyReading {
        if planetFitnessClubURL(query: query) != nil {
            return try await planetFitness.fetch(query: query)
        }
        return try await google.fetch(query: query)
    }
}
