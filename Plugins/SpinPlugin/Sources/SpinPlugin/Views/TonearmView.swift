import SwiftUI

/// A slim arm hinged at its pivot. Angle 0 points straight down; positive
/// swings the tip left, which is SwiftUI's clockwise rotation.
struct TonearmView: View {
    let frame: TonearmFrame
    let isPlaying: Bool

    var body: some View {
        let width = max(3, frame.length * 0.028)
        VStack(spacing: 0) {
            Capsule().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: frame.length)
            RoundedRectangle(cornerRadius: width * 0.4)
                .fill(Color(white: 0.2))
                .frame(width: width * 3, height: width * 4)
        }
        .rotationEffect(.degrees(isPlaying ? frame.playAngle : frame.restAngle), anchor: .top)
        .animation(.easeInOut(duration: 1.2), value: isPlaying)
        .shadow(color: .black.opacity(0.4), radius: width, x: width, y: width)
        .overlay(alignment: .top) {
            Circle().fill(Color(white: 0.3)).frame(width: width * 5, height: width * 5).offset(y: -width * 2.5)
        }
        .frame(width: frame.length * 0.2, height: frame.length * 2, alignment: .top)
        .position(x: frame.pivot.x, y: frame.pivot.y + frame.length)
    }
}
