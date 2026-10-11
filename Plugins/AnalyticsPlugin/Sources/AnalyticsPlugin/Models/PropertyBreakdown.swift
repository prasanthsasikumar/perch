import Foundation

/// The week behind a property's headline numbers, split every way that helps
/// tell people from bots. Fetched on demand for the detail window and never
/// cached: it is seven reports, and only worth it when someone is looking.
public struct PropertyBreakdown: Equatable, Sendable {
    public enum Dimension: String, CaseIterable, Sendable {
        case source = "sessionSourceMedium"
        case country
        case city
        case device = "deviceCategory"
        case browser
        case landingPage
        case hostName

        public var title: String {
            switch self {
            case .source: "Sources"
            case .country: "Countries"
            case .city: "Cities"
            case .device: "Devices"
            case .browser: "Browsers"
            case .landingPage: "Landing pages"
            case .hostName: "Hostnames"
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var value: String
        public var totals: PropertyStats.Totals

        public var id: String { value }

        public init(value: String, totals: PropertyStats.Totals) {
            self.value = value
            self.totals = totals
        }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var dimension: Dimension
        public var rows: [Row]

        public var id: String { dimension.rawValue }

        public init(dimension: Dimension, rows: [Row]) {
            self.dimension = dimension
            self.rows = rows
        }
    }

    /// The whole week, undivided.
    public var totals: PropertyStats.Totals
    /// In `Dimension.allCases` order.
    public var sections: [Section]

    public init(totals: PropertyStats.Totals, sections: [Section]) {
        self.totals = totals
        self.sections = sections
    }
}
