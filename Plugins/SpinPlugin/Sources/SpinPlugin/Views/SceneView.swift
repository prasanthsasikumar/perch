import SwiftUI

/// The whole desktop scene for the selected scene and current track.
struct SceneView: View {
    let model: SpinModel
    let background: NSImage

    var body: some View {
        GeometryReader { geometry in
            if let scene = model.selectedScene {
                let frames = SceneLayout.frames(for: scene.descriptor, imageSize: background.size, in: geometry.size)
                let title = model.nowPlaying?.track?.title ?? ""
                let isPlaying = model.nowPlaying?.state == .playing
                ZStack(alignment: .topLeading) {
                    Image(nsImage: background)
                        .resizable()
                        .frame(width: frames.imageRect.width, height: frames.imageRect.height)
                        .position(x: frames.imageRect.midX, y: frames.imageRect.midY)
                    SleeveView(artwork: model.artwork, title: title, width: frames.sleeveSize,
                               height: frames.sleeveHeight, rotation: frames.sleeveRotation,
                               skew: frames.sleeveSkew, light: scene.descriptor.lightColor,
                               style: scene.descriptor.sleeve.style)
                        .position(frames.sleeveCenter)
                    // Patches of the photo (the stand's lip) back over the sleeve.
                    ForEach(Array(frames.occluders.enumerated()), id: \.offset) { _, outline in
                        Image(nsImage: background)
                            .resizable()
                            .frame(width: frames.imageRect.width, height: frames.imageRect.height)
                            .position(x: frames.imageRect.midX, y: frames.imageRect.midY)
                            .mask {
                                Path { path in path.addLines(outline); path.closeSubpath() }
                            }
                    }
                    RecordView(artwork: model.artwork, fallbackTitle: title, radius: frames.platterRadius,
                               squash: frames.squash, motion: model.motion, light: scene.descriptor.lightColor,
                               animate: model.isAnimating && !model.isScreenAsleep)
                        .position(frames.platterCenter)
                    if let arm = frames.tonearm {
                        TonearmView(frame: arm, isPlaying: isPlaying)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: model.artwork)
            }
        }
        .ignoresSafeArea()
    }
}
