import Foundation

/// Where a scene's drawn parts sit on its background photo.
///
/// Every number is a fraction of the photo (origin top-left, y down) so one
/// file serves every screen. Lengths are fractions of the photo's width.
struct SceneDescriptor: Codable, Equatable, Identifiable, Sendable {
    struct Platter: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var radius: Double
        /// Vertical scale of the record ellipse: the photo looks down at an angle.
        var squash: Double
    }

    /// Angles in degrees: 0 points straight down from the pivot, positive
    /// swings the tip toward the left.
    struct Tonearm: Codable, Equatable, Sendable {
        var pivotX: Double
        var pivotY: Double
        var length: Double
        var restAngle: Double
        var playAngle: Double
    }

    struct Sleeve: Codable, Equatable, Sendable {
        enum Style: String, Codable, Sendable {
            /// Upright in a stand, facing the viewer.
            case stand
            /// Lying on the desk, tipped away in perspective.
            case flat
        }

        var x: Double
        var y: Double
        var size: Double
        var rotation: Double
        var style: Style
    }

    var id: String
    var name: String
    var order: Int
    var platter: Platter
    /// `nil` when the photo already shows its own arm.
    var tonearm: Tonearm?
    var sleeve: Sleeve
}
