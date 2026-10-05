import Foundation

/// One bar of the popular-times histogram: how busy a place usually is at
/// this hour, on the selected day, as Google's 0–100 figure.
public struct HourBusyness: Codable, Equatable {
    /// 0–23, in the place's local time.
    public let hour: Int
    public let percent: Int

    public init(hour: Int, percent: Int) {
        self.hour = hour
        self.percent = percent
    }
}

/// What the page said about a place.
///
/// `statusText` is Google's own phrasing ("A little busy") with the `Live:`
/// prefix stripped; `isLive` records whether that prefix was there. Google
/// shows live data only when it has enough recent visitors to be sure, so
/// every live field is optional and the usual figures stand in when they
/// are missing.
public struct BusyReading: Codable, Equatable {
    public var name: String?
    public var statusText: String?
    public var isLive: Bool
    public var livePercent: Int?
    public var usualPercent: Int?
    /// The hour the live and usual figures belong to, in the place's local
    /// time. Read from the page rather than the Mac's clock, because the
    /// place and the Mac may be in different time zones.
    public var currentHour: Int?
    /// 1 (Monday) to 7 (Sunday), as Google's day tabs number them.
    public var day: Int?
    public var hours: [HourBusyness]
    /// People in the club right now and its capacity, when the source counts
    /// heads (Planet Fitness does; Google never does).
    public var headcount: Int?
    public var capacity: Int?

    public init(
        name: String? = nil,
        statusText: String? = nil,
        isLive: Bool = false,
        livePercent: Int? = nil,
        usualPercent: Int? = nil,
        currentHour: Int? = nil,
        day: Int? = nil,
        hours: [HourBusyness] = [],
        headcount: Int? = nil,
        capacity: Int? = nil
    ) {
        self.name = name
        self.statusText = statusText
        self.isLive = isLive
        self.livePercent = livePercent
        self.usualPercent = usualPercent
        self.currentHour = currentHour
        self.day = day
        self.hours = hours
        self.headcount = headcount
        self.capacity = capacity
    }

    public var level: BusyLevel {
        BusyLevel.from(statusText: statusText, percent: isLive ? livePercent : usualPercent)
    }

    /// The one line under a place's name.
    ///
    /// Leads with Google's words when it has them, because "A little busy"
    /// means more to a person than 78%; the numbers follow so the words can
    /// be checked against the histogram.
    /// The percent the chart's full bar height stands for. Google's figures
    /// are relative to the place's own peak, so 100. A head count is a share
    /// of capacity that rarely passes a fifth, so its chart scales to the
    /// day's busiest hour (or the live figure, if that is higher).
    public var chartCeiling: Int {
        guard capacity != nil else { return 100 }
        return max(1, hours.map(\.percent).max() ?? 0, livePercent ?? 0)
    }

    public var summary: String {
        if isLive {
            var parts: [String] = []
            if let statusText { parts.append(statusText) }
            if let livePercent, let headcount, let capacity {
                // A head count is a share of capacity, not Google's relative
                // busyness, so it reads as "full" with the people behind it.
                parts.append("\(livePercent)% full")
                parts.append("\(headcount) of \(capacity) people")
            } else if let livePercent {
                var figure = "\(livePercent)% now"
                if let usualPercent { figure += ", usually \(usualPercent)%" }
                parts.append(figure)
            }
            return parts.isEmpty ? "Live" : parts.joined(separator: " · ")
        }
        if let statusText { return statusText }
        if let usualPercent { return "Usually \(usualPercent)% at this hour" }
        return "No busyness data"
    }
}

/// A reading plus when it was taken.
public struct Busyness: Codable, Equatable {
    public var reading: BusyReading
    public var fetchedAt: Date

    public init(reading: BusyReading, fetchedAt: Date) {
        self.reading = reading
        self.fetchedAt = fetchedAt
    }
}

/// Three buckets, because that is how many colours a menu bar panel can
/// carry without a legend.
public enum BusyLevel: Equatable {
    case quiet
    case moderate
    case busy
    case unknown

    /// Google's wording first, the percentage as a fallback.
    ///
    /// The wording is checked most-specific first: "not too busy" contains
    /// "busy", and "a little busy" contains it too, so a naive `contains`
    /// would call everything busy. The phrasings are the ones Google has
    /// been observed to use; an unrecognised one falls through to the
    /// percentage rather than to `.unknown`.
    public static func from(statusText: String?, percent: Int?) -> BusyLevel {
        if let text = statusText?.lowercased() {
            if text.contains("not busy") || text.contains("not too busy") { return .quiet }
            if text.contains("little busy") { return .moderate }
            if text.contains("as busy as it gets") || text.contains("very busy") { return .busy }
            if text.contains("busy") { return .busy }
        }
        guard let percent else { return .unknown }
        if percent < 40 { return .quiet }
        if percent < 70 { return .moderate }
        return .busy
    }
}
