import SwiftUI

/// A record seen from above at an angle: grooved disc, album-art label,
/// static sheen. Only the disc and label turn; light does not.
struct RecordView: View {
    let artwork: NSImage?
    let fallbackTitle: String
    let radius: CGFloat
    let squash: CGFloat
    let motion: SpinMotion
    let light: Color
    let animate: Bool

    var body: some View {
        TimelineView(.animation(paused: !animate)) { context in
            ZStack {
                ZStack {
                    Circle().fill(Color(white: 0.05))
                    ForEach(1..<16) { ring in
                        Circle()
                            .stroke(Color.white.opacity(ring.isMultiple(of: 4) ? 0.07 : 0.03), lineWidth: 1)
                            .padding(radius * (0.38 + CGFloat(ring) * 0.035))
                    }
                    label
                        .frame(width: radius * 0.72, height: radius * 0.72)
                        .clipShape(Circle())
                        .colorMultiply(light)
                    Circle().fill(Color(white: 0.75)).frame(width: radius * 0.04, height: radius * 0.04)
                }
                .rotationEffect(.degrees(motion.angle(at: context.date)))
                Circle()
                    .fill(AngularGradient(
                        colors: [.clear, .white.opacity(0.12), .clear, .clear, .white.opacity(0.08), .clear],
                        center: .center
                    ))
                    .blendMode(.screen)
            }
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(x: 1, y: squash)
            // The record's edge: a sliver of its thickness below the top face.
            .background(
                Ellipse()
                    .fill(Color(white: 0.02))
                    .frame(width: radius * 2, height: radius * 2 * squash)
                    .offset(y: radius * 0.018)
            )
            .shadow(color: .black.opacity(0.45), radius: radius * 0.05, y: radius * 0.03)
        }
    }

    @ViewBuilder private var label: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(red: 0.62, green: 0.18, blue: 0.16)
                Text(fallbackTitle)
                    .font(.system(size: max(6, radius * 0.06), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(radius * 0.08)
            }
        }
    }
}
