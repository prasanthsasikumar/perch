import CoreGraphics

struct TonearmFrame: Equatable {
    var pivot: CGPoint
    var length: CGFloat
    var restAngle: Double
    var playAngle: Double
}

/// A scene placed on a particular screen, in screen points.
struct SceneFrames: Equatable {
    var imageRect: CGRect
    var platterCenter: CGPoint
    var platterRadius: CGFloat
    var squash: CGFloat
    var tonearm: TonearmFrame?
    var sleeveCenter: CGPoint
    var sleeveSize: CGFloat
    var sleeveRotation: Double
}

/// Aspect-fills the background onto the screen (cropping, never letterboxing)
/// and carries every drawn part along with it.
enum SceneLayout {
    static func frames(for scene: SceneDescriptor, imageSize: CGSize, in screen: CGSize) -> SceneFrames {
        let scale = max(screen.width / imageSize.width, screen.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let imageRect = CGRect(
            x: (screen.width - drawn.width) / 2,
            y: (screen.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: imageRect.minX + x * drawn.width, y: imageRect.minY + y * drawn.height)
        }
        func length(_ fraction: Double) -> CGFloat { fraction * drawn.width }

        return SceneFrames(
            imageRect: imageRect,
            platterCenter: point(scene.platter.x, scene.platter.y),
            platterRadius: length(scene.platter.radius),
            squash: scene.platter.squash,
            tonearm: scene.tonearm.map {
                TonearmFrame(pivot: point($0.pivotX, $0.pivotY), length: length($0.length),
                             restAngle: $0.restAngle, playAngle: $0.playAngle)
            },
            sleeveCenter: point(scene.sleeve.x, scene.sleeve.y),
            sleeveSize: length(scene.sleeve.size),
            sleeveRotation: scene.sleeve.rotation
        )
    }
}
