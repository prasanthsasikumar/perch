import CoreGraphics
import Foundation
import SwiftUI

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
    var sleeveHeight: CGFloat
    var sleeveRotation: Double
    var sleeveSkew: Double
    var occluders: [[CGPoint]] = []
    /// The sleeve's corners on screen, when the scene gives them.
    var sleeveCorners: [CGPoint]? = nil
}

enum SleeveGeometry {
    /// The perspective transform taking a width×height view at the origin
    /// onto `quad` (top-left, top-right, bottom-right, bottom-left), or nil
    /// when the quad is degenerate.
    static func homography(width: CGFloat, height: CGFloat, to quad: [CGPoint]) -> ProjectionTransform? {
        guard quad.count == 4 else { return nil }
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: width, y: height), CGPoint(x: 0, y: height)]
        var a = [[Double]](), b = [Double]()
        for (s, d) in zip(source, quad) {
            let (x, y, u, v) = (Double(s.x), Double(s.y), Double(d.x), Double(d.y))
            a.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
            a.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
        }
        // Gauss-Jordan with partial pivoting on the 8×8 system.
        for c in 0..<8 {
            guard let p = (c..<8).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[p][c]) > 1e-9 else { return nil }
            a.swapAt(c, p); b.swapAt(c, p)
            for r in 0..<8 where r != c {
                let f = a[r][c] / a[c][c]
                for k in c..<8 { a[r][k] -= f * a[c][k] }
                b[r] -= f * b[c]
            }
        }
        let h = (0..<8).map { CGFloat(b[$0] / a[$0][$0]) }
        return ProjectionTransform(CATransform3D(
            m11: h[0], m12: h[3], m13: 0, m14: h[6],
            m21: h[1], m22: h[4], m23: 0, m24: h[7],
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: h[2], m42: h[5], m43: 0, m44: 1
        ))
    }

    /// Shears a view of `size` about its centre: vertical edges stay
    /// vertical, horizontal edges slope by `degrees` (negative rises to the
    /// right).
    static func shear(degrees: Double, size: CGSize) -> CGAffineTransform {
        let k = tan(degrees * .pi / 180)
        return CGAffineTransform(a: 1, b: k, c: 0, d: 1, tx: 0, ty: -k * size.width / 2)
    }
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
            sleeveHeight: length(scene.sleeve.size) * (scene.sleeve.aspect ?? 1),
            sleeveRotation: scene.sleeve.rotation,
            sleeveSkew: scene.sleeve.skew ?? 0,
            occluders: (scene.occluders ?? []).map { outline in
                outline.compactMap { $0.count == 2 ? point($0[0], $0[1]) : nil }
            },
            sleeveCorners: scene.sleeve.corners.flatMap { corners in
                let points = corners.compactMap { $0.count == 2 ? point($0[0], $0[1]) : nil }
                return points.count == 4 ? points : nil
            }
        )
    }
}
