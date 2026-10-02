import SwiftUI
import TapKit

/// MacTap's side colours: orange left, blue right.
func accent(for side: TapSide) -> Color {
    side == .left ? .orange : .blue
}

/// Three ticks, `count` of them lit.
struct KnockTicks: View {
    var count: Int
    var color: Color = .orange

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i <= count ? color : Color.primary.opacity(0.14))
                    .frame(width: i <= count ? 9 : 6, height: 6)
            }
        }
        .frame(width: 36, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A laptop seen from above, with an edge that lights where the knock was.
struct ChassisSilhouette: View {
    var leftHot: Double = 0
    var rightHot: Double = 0
    var unified = false

    var body: some View {
        HStack(spacing: 8) {
            if !unified {
                Capsule()
                    .fill(Color.orange.opacity(0.18 + leftHot * 0.72))
                    .frame(width: 5)
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: 1)
                        .frame(width: 54, height: 18)
                        .offset(y: 10)
                }
                .overlay {
                    if unified {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.18 + max(leftHot, rightHot) * 0.55), lineWidth: 1.2)
                    }
                }
            if !unified {
                Capsule()
                    .fill(Color.blue.opacity(0.18 + rightHot * 0.72))
                    .frame(width: 5)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.25), value: leftHot)
        .animation(.easeOut(duration: 0.25), value: rightHot)
        .accessibilityHidden(true)
    }
}

/// A trace of recent readings, with the knock threshold dashed across it.
struct WaveformView: View {
    let history: [Float]
    var threshold: Double = 0.04
    var maxDisplay: Double = 0.12
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let threshY = h - CGFloat(min(threshold / maxDisplay, 1)) * (h - 8) - 4

            var thresh = Path()
            thresh.move(to: CGPoint(x: 0, y: threshY))
            thresh.addLine(to: CGPoint(x: w, y: threshY))
            context.stroke(thresh, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            guard history.count > 1 else { return }
            let step = w / CGFloat(history.count - 1)
            var path = Path()
            for (i, value) in history.enumerated() {
                let x = CGFloat(i) * step
                let n = min(Double(value) / maxDisplay, 1.0)
                let y = h - CGFloat(n) * (h - 8) - 4
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.addLine(to: CGPoint(x: 0, y: h))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)
            ))
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

struct PulseDot: View {
    var isOn: Bool
    var color: Color = .green

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: 10, height: 10)
            }
            Circle()
                .fill(isOn ? color : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
        }
        .accessibilityHidden(true)
    }
}

/// Every action, grouped the way MacTap groups them.
struct ActionPicker: View {
    @Binding var selection: ActionType

    var body: some View {
        Picker("Action", selection: $selection) {
            ForEach(ActionCategory.allCases) { category in
                Section(category.title) {
                    ForEach(category.types) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// Live sensor data flows only while one of these is on screen.
struct LiveSensorLease: ViewModifier {
    let store: TapStore

    func body(content: Content) -> some View {
        content
            .onAppear { store.beginLive() }
            .onDisappear { store.endLive() }
    }
}

extension View {
    func streamsLiveSensor(_ store: TapStore) -> some View {
        modifier(LiveSensorLease(store: store))
    }
}
