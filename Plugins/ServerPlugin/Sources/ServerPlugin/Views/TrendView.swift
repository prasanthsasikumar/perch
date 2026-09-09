import SwiftUI

/// The CPU trend for as long as Perch has been watching. Deliberately
/// unlabelled — it is there to show shape, and the current figure is in the
/// meter above.
struct TrendView: View {
    let points: [TrendPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Capsule(style: .continuous)
                    .fill(.tint)
                    // A floor of 2pt so an idle sample reads as a moment with
                    // nothing happening rather than as a gap in the data.
                    .frame(height: max(2, 18 * min(max(point.cpu, 0), 100) / 100))
                    .opacity(point.cpu < 1 ? 0.3 : 1)
            }
        }
        .frame(height: 18)
        .accessibilityLabel("CPU over the last \(points.count) checks")
    }
}
