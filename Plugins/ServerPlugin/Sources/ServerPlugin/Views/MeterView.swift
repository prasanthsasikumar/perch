import SwiftUI

/// A labelled bar: the one repeated unit a health card is made of.
///
/// The colour is the reading, not decoration, so the thresholds live with the
/// alert rules rather than being invented here.
struct MeterView: View {
    let title: String
    let value: String
    /// 0...1. Values above 1 are clamped, which matters for load, where 3.0 on
    /// one core is real and would otherwise draw off the end of the bar.
    let fraction: Double
    var warning: Double = 0.75
    var critical: Double = 0.9
    var caption: String?

    private var clamped: Double { min(max(fraction, 0), 1) }

    private var tint: Color {
        if fraction >= critical { return .red }
        if fraction >= warning { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * clamped))
                }
            }
            .frame(height: 5)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
