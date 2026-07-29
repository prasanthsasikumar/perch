import SwiftUI

/// Seven bars, one per day. Deliberately unlabelled — it is there to show the
/// shape of the week, and the exact numbers are in the rows underneath.
struct SparklineView: View {
    let points: [PropertyStats.DailyPoint]

    private var peak: Double {
        max(points.map(\.activeUsers).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(points) { point in
                Capsule(style: .continuous)
                    .fill(.tint)
                    // A floor of 2pt so a zero day reads as a day with no
                    // traffic rather than as a gap in the data.
                    .frame(height: max(2, 22 * point.activeUsers / peak))
                    .opacity(point.activeUsers == 0 ? 0.25 : 1)
            }
        }
        .frame(height: 22)
        .accessibilityLabel("Active users over the last \(points.count) days")
    }
}
