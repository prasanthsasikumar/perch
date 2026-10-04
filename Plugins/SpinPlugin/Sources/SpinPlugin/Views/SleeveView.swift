import SwiftUI

struct SleeveView: View {
    let artwork: NSImage?
    let title: String
    let size: CGFloat
    let rotation: Double
    let style: SceneDescriptor.Sleeve.Style

    var body: some View {
        cover
            .frame(width: size, height: size)
            .clipped()
            .overlay(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
            .rotation3DEffect(.degrees(style == .flat ? 58 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.4), radius: size * 0.03, x: size * 0.015, y: size * 0.02)
    }

    @ViewBuilder private var cover: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Text(title).font(.system(size: size * 0.07, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(size * 0.1)
            }
        }
    }
}
