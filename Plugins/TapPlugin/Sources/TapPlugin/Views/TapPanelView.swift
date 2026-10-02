import SwiftUI
import TapKit

/// The dropdown: whether Tap is listening, the last knock and what it ran,
/// and the few settings worth a click from the menu bar. First time round,
/// a short setup instead.
struct TapPanelView: View {
    @Bindable var store: TapStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            notices
            if case .failed(let message) = store.companion {
                failure(message)
            } else if store.status == nil {
                starting
            } else if store.config.hasCompletedOnboarding {
                TapDashboard(store: store)
            } else {
                TapSetupView(store: store)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
        if store.companion == .notResponding {
            Label("Tap stopped answering. Starting it again…", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var starting: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Starting Tap…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tap couldn't start", systemImage: "exclamationmark.triangle")
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

/// MacTap's dashboard.
private struct TapDashboard: View {
    @Bindable var store: TapStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !store.isSensorAvailable {
                Label("This Mac’s motion sensor isn’t accessible", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hero
            rows
            if !store.permissions.canPostEvents {
                Button {
                    store.request(.accessibility)
                } label: {
                    Label("Allow Accessibility", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                Text("Detection works without it. Actions that type need it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PulseDot(isOn: store.isListening)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle).font(.headline)
                Text(sensorCaption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Detection", isOn: Binding(
                get: { store.isListening },
                set: { store.setListening($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(!store.isSensorAvailable)
            .help(store.isListening ? "Stop listening for knocks" : "Listen for knocks")
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ChassisSilhouette(
                leftHot: glow(.left),
                rightHot: glow(.right),
                unified: store.config.layout == .knock
            )
            .frame(height: 54)

            WaveformView(
                history: store.status?.live?.magnitude ?? [],
                threshold: store.config.threshold,
                color: store.lastGesture.map { accent(for: $0.side) } ?? .accentColor
            )
            .frame(height: 36)
            .opacity(store.isListening ? 1 : 0.35)

            HStack {
                Text(heroCaption).font(.caption.weight(.medium))
                Spacer()
                Text(store.isListening ? "\(Int(store.status?.sampleRateHz ?? 0)) Hz" : "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .streamsLiveSensor(store)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            row("Last tap", icon: "hand.tap") {
                if let gesture = store.lastGesture {
                    Text(lastActionCaption(gesture))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.config.layout == .knock ? .orange : accent(for: gesture.side))
                        .lineLimit(1)
                } else {
                    Text("Waiting").font(.caption).foregroundStyle(.tertiary)
                }
            }
            row("Preset", icon: "square.grid.2x2") {
                Menu {
                    ForEach(GesturePreset.allCases) { preset in
                        Button {
                            store.applyPreset(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.icon)
                        }
                    }
                } label: {
                    Text(store.config.currentPreset?.title ?? "Custom").font(.caption.weight(.semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            row("Actions", icon: "bolt.fill") {
                Toggle("Actions", isOn: $store.config.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Off: knocks are still shown, but run nothing")
            }
            row("On-screen overlay", icon: "rectangle.inset.filled") {
                Toggle("On-screen overlay", isOn: $store.config.showHUD)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if store.todayCount > 0 {
                row("Today", icon: "chart.bar") {
                    Text("\(store.todayCount)").font(.caption.weight(.semibold).monospacedDigit())
                }
            }
        }
    }

    private func row<Trailing: View>(_ title: String, icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .frame(minHeight: 22)
    }

    private func glow(_ side: TapSide) -> Double {
        guard let gesture = store.lastGesture else { return 0.12 }
        if store.config.layout == .knock { return 0.9 }
        return gesture.side == side ? 1 : 0.12
    }

    private func pattern(_ gesture: DetectedGesture) -> String {
        store.config.layout == .knock ? gesture.tapWord : "\(gesture.side.displayName) · \(gesture.tapWord)"
    }

    private var heroCaption: String {
        if let gesture = store.lastGesture {
            if let action = store.status?.lastExecuted, action != .none {
                return action.displayName
            }
            return pattern(gesture)
        }
        if store.isListening {
            return store.config.layout == .knock ? "Knock the chassis or desk" : "Tap a chassis edge"
        }
        return store.isSensorAvailable ? "Detection is off" : "No motion sensor"
    }

    private func lastActionCaption(_ gesture: DetectedGesture) -> String {
        if let action = store.status?.lastExecuted, action != .none {
            return "\(pattern(gesture)) · \(action.displayName)"
        }
        return pattern(gesture)
    }

    private var statusTitle: String {
        if !store.isSensorAvailable { return "Unavailable" }
        return store.isListening ? "Listening" : "Paused"
    }

    private var sensorCaption: String {
        guard let status = store.status else { return "" }
        switch status.source {
        case .spu:
            if status.gyroAvailable { return status.isStreaming ? "IMU + gyro" : "Ready" }
            return status.isStreaming ? "Built-in IMU" : "Ready"
        case .keyboardSim:
            return "Debug arrows"
        case .unavailable:
            return status.arrowSimulation ? "Debug arrows" : "No IMU"
        }
    }
}

/// First run: what Tap does, the one permission it needs, and a knock to
/// prove it hears you. MacTap's intro and onboarding, panel-sized.
private struct TapSetupView: View {
    @Bindable var store: TapStore
    @State private var step = 0
    @State private var heard = false

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
                    Text("Step \(step + 1) of 3").font(.caption).foregroundStyle(.secondary)
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
                Button(step == 2 ? "Get Started" : "Continue") {
                    if step == 2 {
                        store.completeOnboarding()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .onChange(of: store.gestureToken) { _, _ in
            if step == 2 { withAnimation(.smooth) { heard = true } }
        }
        .onChange(of: step) { _, newStep in
            if newStep == 2 {
                heard = false
                if !store.isListening, store.isSensorAvailable { store.setListening(true) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            ChassisSilhouette(leftHot: 0.45, rightHot: 0.45, unified: true)
                .frame(height: 72)
        case 1:
            if store.permissions.canPostEvents {
                Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Allow Accessibility…") { store.request(.accessibility) }
                    Text("System Settings opens. Turn on **PerchTap**, the part of Perch that types. This step continues on its own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        default:
            if !store.isSensorAvailable {
                Label("This Mac can’t knock. Original M1 Air and some other models don’t expose the motion sensor.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ChassisSilhouette(leftHot: heard ? 1 : 0.3, rightHot: heard ? 1 : 0.3, unified: true)
                        .frame(height: 60)
                    WaveformView(history: store.status?.live?.magnitude ?? [], threshold: store.config.threshold)
                        .frame(height: 30)
                    if heard, let gesture = store.lastGesture {
                        Text("Got it — \(gesture.tapWord.lowercased()) knock.")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Waiting for a knock…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .streamsLiveSensor(store)
            }
        }
    }

    private var icon: String {
        ["laptopcomputer", "lock.shield", "hand.tap"][min(step, 2)]
    }

    private var title: String {
        ["Knock the MacBook", "Allow Accessibility", "Try a knock"][min(step, 2)]
    }

    private var copy: String {
        [
            "Tap listens to the MacBook’s motion sensor. Knock the chassis — or the desk under it — once, twice, or three times to run a shortcut.",
            "Needed so a knock can send copy, paste, Spotlight and media keys. Detection itself does not need it. Knocks are ignored while you type.",
            "A light knock on the side of the MacBook. Map each knock in Settings → Tap; presets, per-app actions, sounds and the overlay are there too.",
        ][min(step, 2)]
    }
}
