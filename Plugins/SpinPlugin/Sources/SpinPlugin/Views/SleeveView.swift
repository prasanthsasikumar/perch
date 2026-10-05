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
