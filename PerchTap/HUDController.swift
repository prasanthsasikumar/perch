import AppKit
import SwiftUI
import TapKit

/// Floating confirmation when a knock lands. Optional — gated by
/// `TapConfig.showHUD`. Ported from MacTap. Main thread only.
final class HUDController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = HUDModel()

    func flash(_ gesture: DetectedGesture, slot: GestureSlot?, layout: GestureLayout) {
        model.permissionPrompt = false
        show(gesture, slot: slot, layout: layout)
    }

    func flashNeedsAccessibility(layout: GestureLayout) {
        let gesture = DetectedGesture(side: .left, tapCount: 1, timestamp: 0, peakMagnitude: 0, peakX: 0)
        model.permissionPrompt = true
        show(gesture, slot: nil, layout: layout)
    }

    func preview(config: TapConfig) {
        let side: TapSide = config.layout == .knock ? .left : .right
        let tapCount = 2
        let slot = config.resolvedSlot(side: side, tapCount: tapCount, bundleID: nil)
            ?? GestureSlot(side: side, tapCount: tapCount, actionType: .copy)
        let gesture = DetectedGesture(side: side, tapCount: tapCount, timestamp: 0, peakMagnitude: 0.04, peakX: 0.02)
        flash(gesture, slot: slot, layout: config.layout)
    }

    private func show(_ gesture: DetectedGesture, slot: GestureSlot?, layout: GestureLayout) {
        ensurePanel()
        place(side: gesture.side, layout: layout)

        model.gesture = gesture
        model.slot = slot
        model.layout = layout
        model.bounceToken &+= 1

        panel?.orderFrontRegardless()

        hideWork?.cancel()
        withAnimation(HUDMotion.appear) {
            model.visible = true
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(HUDMotion.dismiss) {
                self.model.visible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + HUDMotion.dismissDuration) {
                if !self.model.visible {
                    self.panel?.orderOut(nil)
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HUDMotion.hold, execute: work)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: HUDLayout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: HUDView(model: model))
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.frame = NSRect(origin: .zero, size: HUDLayout.size)
        panel.contentView = host

        self.panel = panel
    }

    private func place(side: TapSide, layout: GestureLayout) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let bias: CGFloat = layout == .knock ? 0 : (side == .left ? -HUDLayout.sideBias : HUDLayout.sideBias)
        let origin = NSPoint(
            x: visible.midX - HUDLayout.size.width / 2 + bias,
            y: visible.midY - HUDLayout.size.height / 2 + HUDLayout.verticalLift
        )
        panel?.setFrame(NSRect(origin: origin, size: HUDLayout.size), display: true)
    }
}

private enum HUDLayout {
    static let size = NSSize(width: 248, height: 236)
    static let sideBias: CGFloat = 108
    static let verticalLift: CGFloat = 18
}

private enum HUDMotion {
    static let hold: TimeInterval = 1.28
    static let dismissDuration: TimeInterval = 0.28
    static let appear: Animation = .spring(response: 0.38, dampingFraction: 0.78)
    static let dismiss: Animation = .easeIn(duration: dismissDuration)
}

private final class HUDModel: ObservableObject {
    @Published var gesture: DetectedGesture?
    @Published var slot: GestureSlot?
    @Published var layout: GestureLayout = .knock
    @Published var visible = false
    @Published var bounceToken = 0
    @Published var permissionPrompt = false
}

private func accent(for side: TapSide) -> Color {
    side == .left ? .orange : .blue
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.clear
            if let gesture = model.gesture {
                card(for: gesture)
                    .opacity(model.visible ? 1 : 0)
                    .scaleEffect(reduceMotion ? 1 : (model.visible ? 1 : 0.88))
                    .offset(y: model.visible ? 0 : 10)
                    .blur(radius: model.visible || reduceMotion ? 0 : 6)
            }
        }
        .frame(width: HUDLayout.size.width, height: HUDLayout.size.height)
        .allowsHitTesting(false)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : HUDMotion.appear, value: model.visible)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : HUDMotion.appear, value: model.bounceToken)
    }

    private func card(for gesture: DetectedGesture) -> some View {
        let layout = model.layout
        let tint = model.permissionPrompt || layout == .knock ? Color.orange : accent(for: gesture.side)
        let action = model.slot?.actionType ?? .none
        let title: String
        let subtitle: String
        let icon: String
        if model.permissionPrompt {
            title = "Allow Accessibility"
            subtitle = "Then knocks can send shortcuts"
            icon = "lock.shield"
        } else {
            let pattern = layout == .knock ? gesture.tapWord : "\(gesture.side.displayName) · \(gesture.tapWord)"
            title = action == .none ? gesture.tapWord : action.displayName
            subtitle = action == .none ? (layout == .knock ? "Anywhere" : gesture.side.displayName) : pattern
            icon = action == .none ? "hand.tap.fill" : action.icon
        }

        return VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: model.bounceToken)
                .frame(width: 72, height: 56)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    let on = index <= gesture.tapCount
                    Capsule(style: .continuous)
                        .fill(on ? tint : Color.primary.opacity(0.16))
                        .frame(width: on ? 16 : 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            if layout == .sides {
                HUDChassisMark(side: gesture.side)
                    .frame(height: 26)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 200)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial)
            } else {
                HUDGlassView(cornerRadius: 22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout == .knock
            ? "\(gesture.tapWord), \(title)"
            : "\(gesture.side.displayName), \(gesture.tapWord), \(title)")
    }
}

private struct HUDChassisMark: View {
    let side: TapSide

    var body: some View {
        HStack(spacing: 5) {
            Capsule(style: .continuous)
                .fill(side == .left ? Color.orange : Color.orange.opacity(0.18))
                .frame(width: 3, height: 20)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.tertiary, lineWidth: 1.15)
                .frame(width: 38, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 16, height: 2.5)
                        .offset(y: 6)
                }
            Capsule(style: .continuous)
                .fill(side == .right ? Color.blue : Color.blue.opacity(0.18))
                .frame(width: 3, height: 20)
        }
        .accessibilityHidden(true)
    }
}

/// AppKit HUD material that samples the desktop behind the window.
private struct HUDGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
    }
}
