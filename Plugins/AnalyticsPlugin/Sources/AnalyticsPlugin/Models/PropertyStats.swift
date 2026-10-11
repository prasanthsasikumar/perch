import Foundation

/// Everything the panel draws for one property, and the whole of what gets
/// cached to disk between launches.
public struct PropertyStats: Codable, Equatable, Sendable {
    /// Metric totals over some window. Every field is a `Double` because GA
    /// returns every metric as a string and rates are fractional; converting
    /// once at the edge keeps the arithmetic in one place.
    public struct Totals: Codable, Equatable, Sendable {
        public var activeUsers: Double
        public var sessions: Double
        public var screenPageViews: Double
        public var bounceRate: Double
        public var averageSessionDuration: Double
        /// Sessions that lasted over ten seconds, saw a second page, or fired a
        /// conversion. The closest thing GA has to "a person was here".
        public var engagedSessions: Double
        /// Total foreground seconds across every user in the window.
        public var userEngagementDuration: Double

        public init(
            activeUsers: Double = 0,
            sessions: Double = 0,
            screenPageViews: Double = 0,
            bounceRate: Double = 0,
            averageSessionDuration: Double = 0,
            engagedSessions: Double = 0,
            userEngagementDuration: Double = 0
        ) {
            self.activeUsers = activeUsers
            self.sessions = sessions
            self.screenPageViews = screenPageViews
            self.bounceRate = bounceRate
            self.averageSessionDuration = averageSessionDuration
            self.engagedSessions = engagedSessions
            self.userEngagementDuration = userEngagementDuration
        }

        // Hand-written so caches from before the engagement metrics existed
        // still decode; those keys are simply absent and read as zero.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func value(_ key: CodingKeys) throws -> Double {
                try container.decodeIfPresent(Double.self, forKey: key) ?? 0
            }
            self.init(
                activeUsers: try value(.activeUsers),
                sessions: try value(.sessions),
                screenPageViews: try value(.screenPageViews),
                bounceRate: try value(.bounceRate),
                averageSessionDuration: try value(.averageSessionDuration),
                engagedSessions: try value(.engagedSessions),
                userEngagementDuration: try value(.userEngagementDuration)
            )
        }

        /// Fewer sessions than this and the engagement rate is noise.
        static let minimumSessionsToJudge: Double = 10
        /// Under this share of engaged sessions, most of the traffic is
        /// crawlers and scanners that load one page and leave in 0s.
        static let botEngagementThreshold = 0.2

        public var engagementRate: Double {
            sessions > 0 ? engagedSessions / sessions : 0
        }

        /// Seconds per user, which is what GA's own "average engagement time"
        /// card shows.
        public var averageEngagementTime: Double {
            activeUsers > 0 ? userEngagementDuration / activeUsers : 0
        }

        public var pagesPerSession: Double {
            sessions > 0 ? screenPageViews / sessions : 0
        }

        public var looksLikeBots: Bool {
            sessions >= Self.minimumSessionsToJudge && engagementRate < Self.botEngagementThreshold
        }

        /// Nobody engaged and nobody stayed: the signature of a bot row.
        public var hasNoEngagement: Bool {
            sessions > 0 && engagedSessions == 0 && userEngagementDuration == 0
        }
    }

    /// One day of the trailing week.
    public struct DailyPoint: Codable, Equatable, Sendable, Identifiable {
        /// GA's `yyyyMMdd`.
        public var date: String
        public var activeUsers: Double
        public var sessions: Double

        public var id: String { date }

        public init(date: String, activeUsers: Double, sessions: Double) {
            self.date = date
            self.activeUsers = activeUsers
            self.sessions = sessions
        }
    }

    public var last30Days: Totals
    public var currentWeek: Totals
    public var previousWeek: Totals
    public var daily: [DailyPoint]

    public init(
        last30Days: Totals = Totals(),
        currentWeek: Totals = Totals(),
        previousWeek: Totals = Totals(),
        daily: [DailyPoint] = []
    ) {
        self.last30Days = last30Days
        self.currentWeek = currentWeek
        self.previousWeek = previousWeek
        self.daily = daily
    }

    public var usersChange: PercentChange {
        PercentChange(current: currentWeek.activeUsers, previous: previousWeek.activeUsers)
    }

    public var sessionsChange: PercentChange {
        PercentChange(current: currentWeek.sessions, previous: previousWeek.sessions)
    }

    /// What the menu bar shows: active users on the most recent day GA has.
    ///
    /// Deliberately not "today" in the Mac's calendar. A property reports in
    /// its own timezone, so one set to Asia/Singapore is already on tomorrow's
    /// date by a New York evening; keying off the laptop's clock would show
    /// yesterday's number while GA's dashboard showed today's. It also handles
    /// the ordinary case where GA has simply not finished processing today —
    /// a missing row is not a day of zero traffic.
    public var latestActiveUsers: Double? {
        daily.last?.activeUsers
    }
}
