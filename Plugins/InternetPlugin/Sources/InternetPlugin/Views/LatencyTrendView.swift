import SwiftUI

/// Where each check sits in a 0...1 box, y flipped for drawing (0 is the top).
///
/// A check with no answer at all is `nil`: it is drawn as a mark along the
/// bottom rather than as a latency of zero, which would read as the fastest
/// the line has ever been.
enum LatencyGeometry {
    struct Point: Equatable {
        var x: Double
        /// `nil` for a check where nothing answered.
        var y: Double?
    }

    /// The ceiling never drops below `floor`, so a quiet line does not get
    /// its few milliseconds of wobble stretched into dramatic peaks.
    static func normalise(_ values: [Double?], floor: Double = 100) -> [Point] {
        guard !values.isEmpty else { return [] }
        let ceiling = max(values.compactMap { $0 }.max() ?? 0, floor)
        let last = Double(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            Point(
                x: values.count == 1 ? 0 : Double(index) / last,
                y: value.map { 1 - min(max($0, 0), ceiling) / ceiling }
            )
        }
    }
}

/// Latency over the last hour of checks, with dropped checks marked in red.
struct LatencyTrendView: View {
    let checks: [Check]

    var body: some View {
        GeometryReader { geometry in
            let points = LatencyGeometry.normalise(checks.map(\.latency))
            let size = geometry.size
            ZStack {
                Path { path in
                    // Broken at every failed check, so a gap looks like a gap.
                    var drawing = false
                    for point in points {
                        guard let y = point.y else { drawing = false; continue }
                        let scaled = CGPoint(x: point.x * size.width, y: y * size.height)
                        if drawing { path.addLine(to: scaled) } else { path.move(to: scaled) }
                        drawing = true
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                Path { path in
                    for point in points where point.y == nil {
                        let x = point.x * size.width
                        path.addRect(CGRect(x: x - 1, y: size.height - 4, width: 2, height: 4))
                    }
                }
                .fill(.red)
            }
        }
        .frame(height: 28)
        .accessibilityLabel("Latency over the last \(checks.count) checks")
    }
}
