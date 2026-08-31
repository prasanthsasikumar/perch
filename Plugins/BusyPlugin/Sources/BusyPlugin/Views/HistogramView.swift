import SwiftUI

extension BusyLevel {
    var color: Color {
        switch self {
        case .quiet: .green
        case .moderate: .yellow
        case .busy: .red
        case .unknown: .secondary
        }
    }
}

/// Today's popular times, one bar per hour Google shows.
///
/// The current hour is drawn twice: the usual bar in grey, and the live bar
/// over it in the level's colour, so "busier than usual" is visible at a
/// glance without reading a number. Only the first and last hours are
/// labelled — the panel is too narrow for more, and the exact figures are in
/// the line above.
struct HistogramView: View {
    let hours: [HourBusyness]
    let currentHour: Int?
    let livePercent: Int?
    let level: BusyLevel

    private static let barHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours, id: \.hour) { entry in
                    bar(for: entry)
                }
            }
            .frame(height: Self.barHeight)

            if let first = hours.first, let last = hours.last {
                HStack {
                    Text(Self.label(first.hour))
                    Spacer()
                    Text(Self.label(last.hour))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Popular times today")
    }

    @ViewBuilder
    private func bar(for entry: HourBusyness) -> some View {
        let isCurrent = entry.hour == currentHour
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isCurrent ? Color.secondary.opacity(0.35) : Color.accentColor.opacity(0.75))
                .frame(height: height(entry.percent))
            if isCurrent, let livePercent {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(level.color)
                    .frame(height: height(livePercent))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(Self.label(entry.hour)): \(entry.percent) percent")
    }

    /// A floor of 2pt so a closed hour reads as an hour with nobody there
    /// rather than as a gap in the data.
    private func height(_ percent: Int) -> CGFloat {
        max(2, Self.barHeight * CGFloat(percent) / 100)
    }

    /// "4a", "12p", "9p" — the shortest form that is still unambiguous.
    static func label(_ hour: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve)\(hour < 12 ? "a" : "p")"
    }
}
