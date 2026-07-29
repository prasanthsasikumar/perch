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

        public init(
            activeUsers: Double = 0,
            sessions: Double = 0,
            screenPageViews: Double = 0,
            bounceRate: Double = 0,
            averageSessionDuration: Double = 0
        ) {
            self.activeUsers = activeUsers
            self.sessions = sessions
            self.screenPageViews = screenPageViews
            self.bounceRate = bounceRate
            self.averageSessionDuration = averageSessionDuration
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
