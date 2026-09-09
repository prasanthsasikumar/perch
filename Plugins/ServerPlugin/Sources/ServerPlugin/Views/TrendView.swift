import SwiftUI

/// Normalised coordinates for the trend line, in a 0...1 unit box with y
/// already flipped for drawing (0 is the top).
///
/// Separated from the view so the one thing that actually went wrong here can
/// be tested: drawing one bar per sample looked fine at two dozen points and
/// silently vanished as the ring buffer filled, because each bar fell below a
/// pixel wide. A line has no such limit.
enum TrendGeometry {
    static func normalise(_ values: [Double], ceiling: Double = 100) -> [CGPoint] {
        guard !values.isEmpty, ceiling > 0 else { return [] }
        guard values.count > 1 else { return [CGPoint(x: 0, y: y(values[0], ceiling))] }
        let last = Double(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: Double(index) / last, y: y(value, ceiling))
        }
    }

    private static func y(_ value: Double, _ ceiling: Double) -> Double {
        let clamped = min(max(value.isFinite ? value : 0, 0), ceiling)
        return 1 - clamped / ceiling
    }
}

/// The CPU trend for as long as Perch has been watching. Deliberately
/// unlabelled — it is there to show shape, and the current figure is in the
/// meter below.
struct TrendView: View {
    let points: [TrendPoint]

    var body: some View {
        GeometryReader { geometry in
            let unit = TrendGeometry.normalise(points.map(\.cpu))
            Path { path in
                guard unit.count > 1 else { return }
                for (index, point) in unit.enumerated() {
                    let scaled = CGPoint(
                        x: point.x * geometry.size.width,
                        y: point.y * geometry.size.height
                    )
                    if index == 0 {
                        path.move(to: scaled)
                    } else {
                        path.addLine(to: scaled)
                    }
                }
            }
            .stroke(
                .tint,
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 18)
        .accessibilityLabel("CPU over the last \(points.count) checks")
    }
}
