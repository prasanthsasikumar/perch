import SwiftUI

/// The album sleeve standing in the scene's stand (or lying on the desk).
///
/// Drawn over the photo, so it cannot slip behind the stand's lip; instead
/// its bottom edge is placed exactly on the lip, which reads the same.
struct SleeveView: View {
    let artwork: NSImage?
    let title: String
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let skew: Double
    let light: Color
    let style: SceneDescriptor.Sleeve.Style

    var body: some View {
        cover
            .frame(width: width, height: height)
            .clipped()
            .colorMultiply(light)
            // Light falls on the top edge; the bottom sits in the stand's shade.
            .overlay(LinearGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.28)],
                                    startPoint: .top, endPoint: .bottom))
            .transformEffect(SleeveGeometry.shear(degrees: skew, size: CGSize(width: width, height: height)))
            .rotation3DEffect(.degrees(style == .flat ? 58 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.35), radius: width * 0.02, x: width * 0.01, y: -width * 0.005)
    }

    @ViewBuilder private var cover: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Text(title).font(.system(size: width * 0.07, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(width * 0.1)
            }
        }
    }
}

extension SceneDescriptor {
    /// `light` as a SwiftUI colour for `colorMultiply`; white when unset.
    var lightColor: Color {
        guard let light, light.count == 3 else { return .white }
        return Color(red: light[0], green: light[1], blue: light[2])
    }
}

/// The sleeve warped onto four corners in true perspective, so it can lean
/// back against a stand instead of standing upright in front of it.
struct QuadSleeveView: View {
    let artwork: NSImage?
    let title: String
    let corners: [CGPoint]
    let light: Color

    /// The art is laid out at this size, then projected onto the corners.
    private let side: CGFloat = 1000

    var body: some View {
        if let projection = SleeveGeometry.homography(width: side, height: side, to: corners) {
            SleeveView(artwork: artwork, title: title, width: side, height: side,
                       rotation: 0, skew: 0, light: light, style: .stand)
                .projectionEffect(projection)
                .frame(width: side, height: side)
                .position(x: side / 2, y: side / 2)
        }
    }
}
