import ScrollKit
import SwiftUI

/// The dropdown: whether scrolls are being reversed, the master switch, and
/// which devices and directions. First time round, a short setup instead.
struct ScrollPanelView: View {
    @Bindable var store: ScrollStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            notices
            if store.isScrollReverserRunning {
                ScrollReverserWarning()
            }
            if case .failed(let message) = store.companion {
                failure(message)
            } else if store.settings.hasCompletedSetup {
                ScrollDashboard(store: store)
            } else {
                ScrollSetupView(store: store)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { store.refreshConflicts() }
    }

    @ViewBuilder
    private var notices: some View {
        if let notice = store.loadFailureNotice {
            Text(notice).font(.caption).foregroundStyle(.orange)
        }
        if let notice = store.saveFailureNotice {
            Text(notice).font(.caption).foregroundStyle(.red)
        }
        if let notice = store.status?.configError {
            Text(notice).font(.caption).foregroundStyle(.red)
        }
        if let notice = store.status?.tapError {
            Text(notice).font(.caption).foregroundStyle(.red)
        }
        if store.companion == .notResponding {
            Label("Scroll stopped answering. Starting it again…", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Scroll couldn't start", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { store.retry() }
                .controlSize(.small)
        }
    }
}

/// Two apps reversing the same wheel put it back the way it was.
struct ScrollReverserWarning: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Scroll Reverser is running", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("With both on, each undoes the other and the wheel seems unchanged. Quit Scroll Reverser from its menu bar icon, and remove it from Login Items so it doesn't start again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Login Items…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    openURL(url)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Set up: the status, the master switch, and the four toggles.
private struct ScrollDashboard: View {
    @Bindable var store: ScrollStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if store.state == .needsAccessibility {
                AccessibilityRequest(store: store)
            } else if store.state == .helperNotRunning {
                Button("Start again") { store.retry() }
                    .controlSize(.small)
            }
            VStack(spacing: 6) {
                ScrollToggleRow(title: "Mouse wheel", icon: "computermouse", isOn: $store.settings.reverseMouse)
                ScrollToggleRow(title: "Trackpad", icon: "hand.point.up.left", isOn: $store.settings.reverseTrackpad)
                Divider()
                ScrollToggleRow(title: "Up and down", icon: "arrow.up.arrow.down", isOn: $store.settings.reverseVertical)
                ScrollToggleRow(title: "Left and right", icon: "arrow.left.arrow.right", isOn: $store.settings.reverseHorizontal)
            }
            .disabled(!store.settings.isOn)
            .opacity(store.settings.isOn ? 1 : 0.5)

            if store.state == .active, let device = store.status?.lastDevice {
                HStack {
                    Label("Last scroll", systemImage: "scroll")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(device.displayName) · \(store.status?.lastWasReversed == true ? "reversed" : "as is")")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(color: dotColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Reverse scrolling", isOn: $store.settings.isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(store.settings.isOn ? "Pause: every scroll passes through unchanged" : "Reverse scrolling")
        }
    }

    private var title: String {
        switch store.state {
        case .starting: "Starting…"
        case .active: "Active"
        case .needsAccessibility: "Needs Accessibility permission"
        case .paused: "Paused"
        case .helperNotRunning: "Helper not running"
        }
    }

    private var caption: String {
        switch store.state {
        case .starting: "Waiting for PerchScroll"
        case .active: summary
        case .needsAccessibility: "macOS won't let PerchScroll change scrolls yet"
        case .paused:
            store.settings.isOn ? "Nothing is set to be reversed" : "Every scroll passes through unchanged"
        case .helperNotRunning: "PerchScroll, the part that reverses, isn't answering"
        }
    }

    private var summary: String {
        let s = store.settings
        let mouse = s.reverseMouse ? "Mouse reversed" : "Mouse as is"
        let trackpad = s.reverseTrackpad ? "trackpad reversed" : "trackpad as is"
        return "\(mouse) · \(trackpad)"
    }

    private var dotColor: Color {
        switch store.state {
        case .active: .green
        case .needsAccessibility, .helperNotRunning: .orange
        case .starting, .paused: Color.secondary.opacity(0.35)
        }
    }
}

/// First run: what Scroll does, and the one permission it needs.
private struct ScrollSetupView: View {
    @Bindable var store: ScrollStore
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text("Step \(step + 1) of 2").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(copy)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Button(step == 1 ? "Get Started" : "Continue") {
                    if step == 1 {
                        store.completeSetup()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .onChange(of: step) { _, newStep in
            if newStep == 1 { store.beginSetup() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 6) {
                DeviceDirectionRow(icon: "computermouse", device: "Mouse wheel", effect: "Reversed", highlighted: true)
                DeviceDirectionRow(icon: "hand.point.up.left", device: "Trackpad", effect: "Natural", highlighted: false)
            }
        default:
            if store.isTrusted {
                Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if store.companion != .running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting PerchScroll…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                AccessibilityRequest(store: store)
            }
        }
    }

    private var icon: String {
        ["computermouse", "lock.shield"][min(step, 1)]
    }

    private var title: String {
        ["Reverse the mouse wheel", "Allow Accessibility"][min(step, 1)]
    }

    private var copy: String {
        [
            "macOS has one natural-scrolling switch for every device. Scroll turns the mouse wheel around and leaves the trackpad as it is. Either device, and each direction, can be changed later.",
            "To turn a scroll around, Perch has to catch it on its way to the app under the pointer, and macOS allows that only with Accessibility. Scroll looks at scroll events and nothing else, flips the ones you chose, and keeps none of them.",
        ][min(step, 1)]
    }
}

/// The button that asks for Accessibility, and what will happen.
private struct AccessibilityRequest: View {
    let store: ScrollStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.requestAccessibility()
            } label: {
                Label("Allow Accessibility…", systemImage: "lock.shield")
            }
            Text("System Settings opens. Turn on **PerchScroll**, the part of Perch that reverses the wheel. This continues on its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DeviceDirectionRow: View {
    let icon: String
    let device: String
    let effect: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(device)
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(effect)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 60, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ScrollToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .frame(minHeight: 22)
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: 10, height: 10)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .accessibilityHidden(true)
    }
}
