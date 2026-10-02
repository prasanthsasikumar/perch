import AppKit
import SwiftUI
import TapKit

/// Tap's pane in Perch's Settings: MacTap's five settings panes as tabs.
struct TapSettingsView: View {
    let store: TapStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            GesturesTab(store: store)
                .tabItem { Label("Gestures", systemImage: "hand.tap") }
            SensorTab(store: store)
                .tabItem { Label("Sensor", systemImage: "waveform") }
            SoundTab(store: store)
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            PrivacyTab(store: store)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .padding(.top, 8)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var store: TapStore
    @State private var showCalibration = false
    #if DEBUG
    @State private var simulateArrows = false
    #endif

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    PulseDot(isOn: store.isListening)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.isListening ? "Detection On" : "Detection Off")
                        Text(store.status?.source.displayName ?? "Not running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isListening ? "Stop" : "Start") { store.setListening(!store.isListening) }
                        .controlSize(.small)
                        .disabled(!store.isSensorAvailable && !store.isListening)
                }
                #if DEBUG
                Toggle("Simulate knocks with arrow keys", isOn: $simulateArrows)
                    .onChange(of: simulateArrows) { _, on in store.simulateArrows(on) }
                #endif
                Toggle("Enable gesture actions", isOn: $store.config.enabled)
            } header: {
                Text("Detection")
            } footer: {
                if let footer = detectionFooter {
                    Text(footer).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Slider(value: $store.config.sensitivity, in: 0...1, step: 0.01) { Text("Sensitivity") }
                LabeledContent("Threshold") {
                    Text(String(format: "%.3f g · %@", store.config.threshold, store.config.sensitivityLabel))
                        .font(.caption.monospacedDigit())
                }
            } header: {
                Text("Sensitivity")
            } footer: {
                Text("A firm knuckle on the side edge should fire. If the trackpad or typing also fires, turn this down.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Timing") {
                Slider(value: $store.config.tapGroupingWindow, in: 0.15...0.55, step: 0.01) {
                    Text("Multi-tap window")
                }
                LabeledContent("Window", value: String(format: "%.2f s", store.config.tapGroupingWindow))
                Slider(value: $store.config.actionCooldown, in: 0.05...0.6, step: 0.01) {
                    Text("Action cooldown")
                }
                LabeledContent("Cooldown", value: String(format: "%.2f s", store.config.actionCooldown))
            }

            Section {
                Toggle("Show on-screen overlay", isOn: $store.config.showHUD)
                if store.config.showHUD {
                    Button("Preview Overlay") { store.previewHUD() }
                }
            } header: {
                Text("Overlay")
            } footer: {
                Text("A short confirmation appears when a gesture is recognized.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if store.config.layout == .sides {
                    Toggle("Invert left and right", isOn: $store.config.invertSides)
                }
                Toggle("Ignore taps while typing", isOn: $store.config.ignoreWhileTyping)
                if store.config.layout == .sides {
                    Button("Calibrate Left / Right…") { showCalibration = true }
                }
                Button("Replay setup") { store.replayOnboarding() }
            } header: {
                Text("Accuracy")
            } footer: {
                Text(store.config.layout == .knock
                    ? "Anywhere ignores left vs right. Knocks are ignored for a moment after any key so typing does not fire actions."
                    : TapDetector.sideHeuristicDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Reset Settings", role: .destructive) { store.resetSettings() }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(store: store) { showCalibration = false }
                .frame(width: 400, height: 340)
        }
        #if DEBUG
        .onAppear { simulateArrows = store.status?.arrowSimulation ?? false }
        #endif
    }

    private var detectionFooter: String? {
        guard let status = store.status else {
            return "Tap's engine is not running. Turn the plugin on in Settings → Plugins."
        }
        if !status.isSensorAvailable {
            return "This Mac’s motion sensor isn’t accessible. Detection stays off so the keyboard is untouched."
        }
        if status.source == .keyboardSim {
            return "Debug only: Left/Right arrows inject fake taps. They never send shortcuts."
        }
        if status.isStreaming {
            return "Receiving \(Int(status.sampleRateHz)) Hz from the built-in motion sensor. Tap runs whenever Perch does."
        }
        return nil
    }
}

// MARK: - Gestures

private struct GesturesTab: View {
    @Bindable var store: TapStore
    @State private var expandedRuleID: UUID?

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: $store.config.layout) {
                    ForEach(GestureLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Menu {
                    ForEach(GesturePreset.allCases) { preset in
                        Button {
                            store.applyPreset(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.icon)
                        }
                    }
                } label: {
                    LabeledContent("Preset", value: store.config.currentPreset?.title ?? "Custom")
                }
            } footer: {
                Text(presetFooter).font(.caption).foregroundStyle(.secondary)
            }

            if store.config.layout == .knock {
                Section("Actions") {
                    ForEach(store.slots(for: .left)) { slot in
                        GestureSlotRow(store: store, slot: slot, layout: .knock)
                    }
                }
            } else {
                Section("Left") {
                    ForEach(store.slots(for: .left)) { slot in
                        GestureSlotRow(store: store, slot: slot, layout: .sides)
                    }
                }
                Section("Right") {
                    ForEach(store.slots(for: .right)) { slot in
                        GestureSlotRow(store: store, slot: slot, layout: .sides)
                    }
                }
            }

            Section {
                Menu {
                    Button("Frontmost app") { addRuleForFrontmost() }
                    Divider()
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") { addRule(for: app) }
                    }
                } label: {
                    Label("Add app", systemImage: "plus")
                }
                ForEach(store.config.appRules) { rule in
                    AppRuleRow(
                        store: store,
                        rule: rule,
                        isExpanded: expandedRuleID == rule.id
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            expandedRuleID = expandedRuleID == rule.id ? nil : rule.id
                        }
                    }
                }
            } header: {
                Text("Per app")
            } footer: {
                Text(store.config.layout == .knock
                    ? "When that app is frontmost, these knocks replace the ones above."
                    : "When that app is frontmost, listed taps replace the global ones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var presetFooter: String {
        if let preset = store.config.currentPreset {
            return store.config.layout == .knock ? preset.knockLine : preset.subtitle
        }
        return "Custom mix of actions."
    }

    /// Apps a person would want a rule for: regular ones, not Perch's own.
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.bundleIdentifier != nil
                    && app.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// Does nothing while Perch's own window is in front; `addRule` refuses Perch.
    private func addRuleForFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        addRule(for: app)
    }

    private func addRule(for app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        expandedRuleID = store.addRule(bundleID: bundleID, appName: app.localizedName ?? bundleID)
    }
}

private struct GestureSlotRow: View {
    let store: TapStore
    let slot: GestureSlot
    let layout: GestureLayout
    @State private var parameter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                KnockTicks(count: slot.tapCount, color: layout == .knock ? .orange : accent(for: slot.side))
                Text(slot.label(layout: layout))
                    .frame(minWidth: 56, alignment: .leading)
                Spacer(minLength: 8)
                ActionPicker(selection: Binding(
                    get: { slot.actionType },
                    set: { action in
                        var updated = slot
                        updated.actionType = action
                        store.updateSlot(updated)
                    }
                ))
                Button {
                    store.test(slot)
                } label: {
                    Image(systemName: "play.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Test this action")
                .accessibilityLabel("Test \(slot.label(layout: layout))")
            }
            if slot.actionType.needsParameter {
                TextField(slot.actionType.parameterPlaceholder, text: $parameter, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .font(slot.actionType == .shellCommand || slot.actionType == .appleScript
                        ? .system(.body, design: .monospaced) : .body)
                    .onChange(of: parameter) { _, value in
                        guard value != slot.parameter else { return }
                        var updated = slot
                        updated.parameter = value
                        store.updateSlot(updated)
                    }
            }
        }
        .onAppear { parameter = slot.parameter }
        .onChange(of: slot.parameter) { _, value in
            if value != parameter { parameter = value }
        }
    }
}

private struct AppRuleRow: View {
    @Bindable var store: TapStore
    let rule: AppRule
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                appIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.appName)
                    Text(rule.enabled ? (rule.slots.isEmpty ? "Uses global actions" : "\(rule.slots.count) custom") : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(1...3, id: \.self) { count in
                        overrideRow(side: .left, tapCount: count)
                    }
                    if store.config.layout == .sides {
                        ForEach(1...3, id: \.self) { count in
                            overrideRow(side: .right, tapCount: count)
                        }
                    }
                    Button("Remove", role: .destructive) { store.removeRule(rule.id) }
                        .controlSize(.small)
                }
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").foregroundStyle(.secondary).frame(width: 20)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { on in
                if let index = store.config.appRules.firstIndex(where: { $0.id == rule.id }) {
                    store.config.appRules[index].enabled = on
                }
            }
        )
    }

    private func overrideRow(side: TapSide, tapCount: Int) -> some View {
        let layout = store.config.layout
        let label = GestureSlot(side: side, tapCount: tapCount, actionType: .none).label(layout: layout)
        return HStack(spacing: 8) {
            KnockTicks(count: tapCount, color: layout == .knock ? .orange : accent(for: side))
            Text(label)
                .font(.caption)
                .frame(width: layout == .knock ? 52 : 88, alignment: .leading)
            Picker("Action", selection: Binding<ActionType?>(
                get: { rule.override(side: side, tapCount: tapCount)?.actionType },
                set: { store.setOverride($0, side: side, tapCount: tapCount, inRule: rule.id) }
            )) {
                Text("Inherit").tag(ActionType?.none)
                ForEach(ActionCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(category.types) { type in
                            Text(type.displayName).tag(ActionType?.some(type))
                        }
                    }
                }
            }
            .labelsHidden()
        }
    }
}

// MARK: - Sensor

private struct SensorTab: View {
    let store: TapStore

    var body: some View {
        Form {
            Section("Live") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Magnitude").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(store.status?.sampleRateHz ?? 0)) Hz")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    WaveformView(history: live?.magnitude ?? [], threshold: store.config.threshold)
                        .frame(height: 100)
                    ChassisSilhouette(
                        leftHot: glow(.left),
                        rightHot: glow(.right),
                        unified: store.config.layout == .knock
                    )
                    .frame(height: 40)
                }
                .padding(.vertical, 4)
            }

            Section("Status") {
                if !store.isSensorAvailable {
                    Text("This Mac’s motion sensor isn’t accessible. Knock detection is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: store.isListening ? "Streaming" : "Idle")
                LabeledContent("Source", value: store.status?.source.displayName ?? "—")
                LabeledContent("Rate", value: "\(Int(store.status?.sampleRateHz ?? 0)) Hz")
                LabeledContent("Samples", value: "\(store.status?.sampleCount ?? 0)")
                if let error = store.status?.lastError {
                    LabeledContent("Last error", value: error)
                }
            }

            Section("Axes") {
                WaveformView(history: (live?.x ?? []).map(abs), color: .orange).frame(height: 40)
                WaveformView(history: (live?.y ?? []).map(abs), color: .green).frame(height: 40)
                WaveformView(history: (live?.z ?? []).map(abs), color: .yellow).frame(height: 40)
            }

            Section("Values") {
                if let live, store.isListening {
                    axisRow("X · lateral", live.sampleX, .orange)
                    axisRow("Y · long", live.sampleY, .green)
                    axisRow("Z · vertical", live.sampleZ, .yellow)
                    axisRow("Magnitude", live.sampleMagnitude, .blue, bold: true)
                    axisRow("Noise floor", live.noiseFloor, .secondary)
                } else {
                    Text("Start detection to see sensor data.").foregroundStyle(.secondary)
                }
            }

            Section("Classifier") {
                LabeledContent("Pending taps", value: "\(live?.pendingTapCount ?? 0)")
                if let gesture = store.lastGesture {
                    LabeledContent("Last gesture", value: store.config.layout == .knock
                        ? gesture.tapWord
                        : "\(gesture.side.displayName) · \(gesture.tapWord)")
                }
                if let reason = live?.lastRejectReason, !reason.isEmpty {
                    LabeledContent("Last reject", value: reason)
                }
            }
        }
        .formStyle(.grouped)
        .streamsLiveSensor(store)
    }

    private var live: LiveFrame? { store.status?.live }

    private func glow(_ side: TapSide) -> Double {
        guard let gesture = store.lastGesture else { return 0.15 }
        if store.config.layout == .knock { return 0.9 }
        return gesture.side == side ? 1 : 0.15
    }

    private func axisRow(_ label: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        LabeledContent {
            Text(String(format: "%+.4f g", value))
                .monospacedDigit()
                .foregroundStyle(bold ? .primary : .secondary)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).fontWeight(bold ? .semibold : .regular)
            }
        }
    }
}

// MARK: - Sound

private struct SoundTab: View {
    @Bindable var store: TapStore

    var body: some View {
        Form {
            Section {
                Toggle("Play a sound on every gesture", isOn: $store.config.soundEnabled)
                Slider(
                    value: Binding(
                        get: { Double(store.config.soundVolume) },
                        set: { store.config.soundVolume = Float($0) }
                    ),
                    in: 0...1
                ) {
                    Text("Volume")
                }
                LabeledContent("Volume", value: "\(Int(store.config.soundVolume * 100))%")
            } header: {
                Text("Playback")
            } footer: {
                Text("Left taps pan left and right taps pan right. Sounds are synthesized, not recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pack") {
                Picker("Sound Pack", selection: $store.config.soundPack) {
                    ForEach(SoundPack.allCases) { pack in
                        Label(pack.rawValue, systemImage: pack.icon).tag(pack)
                    }
                }
                Text(store.config.soundPack.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(store.config.soundPack.sounds, id: \.self) { name in
                        Button {
                            store.preview(sound: name)
                        } label: {
                            Text(name.capitalized).frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    let store: TapStore

    var body: some View {
        Form {
            Section {
                if store.permissions.canPostEvents {
                    Label("Accessibility is allowed. Actions can run.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Tap needs Accessibility to send shortcuts and media keys. Other permissions are optional.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("These are granted to **PerchTap**, the part of Perch that reads the sensor and types — not to Perch itself. Knocks are classified on this Mac; nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            PermissionRow(
                store: store,
                kind: .accessibility,
                title: "Accessibility",
                description: "Required to send Spotlight, copy, paste, and other shortcuts. macOS lists keystroke posting here.",
                isRequired: true
            )
            PermissionRow(
                store: store,
                kind: .inputMonitoring,
                title: "Input Monitoring",
                description: "Optional. Accessibility already pauses knocks while you type; this is a fallback.",
                isRequired: false
            )
            PermissionRow(
                store: store,
                kind: .automation,
                title: "Automation",
                description: "Needed so Tap can ask System Events to type shortcuts (copy, paste, Spotlight).",
                isRequired: true
            )
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let store: TapStore
    let kind: PermissionKind
    let title: String
    let description: String
    let isRequired: Bool

    var body: some View {
        let state = store.permissions.state(of: kind)
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(state == .granted ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.headline)
                        Text(isRequired ? "Required" : "Optional")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isRequired ? .orange : .secondary)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if state != .granted {
                HStack {
                    Button("Allow") { store.request(kind) }
                    Button("System Settings") { store.openSystemSettings(kind) }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Calibration

/// Four knocks on each edge, then whichever way round and offset makes
/// them read as left and right.
private struct CalibrationView: View {
    let store: TapStore
    let onDone: () -> Void
    @State private var leftPeaks: [Double] = []
    @State private var rightPeaks: [Double] = []
    @State private var message = "Tap the left edge four times."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Side Calibration").font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                column("Left", count: leftPeaks.count, color: .orange)
                column("Right", count: rightPeaks.count, color: .blue)
            }

            HStack {
                Button("Reset Samples") {
                    leftPeaks.removeAll()
                    rightPeaks.removeAll()
                    message = "Tap the left edge four times."
                }
                Spacer()
                Button("Done", action: onDone)
                if leftPeaks.count >= 4 && rightPeaks.count >= 4 {
                    Button("Save Calibration") {
                        let swapped = store.commitCalibration(leftPeaks: leftPeaks, rightPeaks: rightPeaks)
                        message = swapped == true
                            ? "Saved. Left and right were swapped for this Mac."
                            : "Saved. Side detection kept as-is."
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding(24)
        .onAppear { store.beginCalibration() }
        .onChange(of: store.gestureToken) { _, _ in ingest() }
    }

    private func column(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(count)/4").font(.title.monospacedDigit().weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ingest() {
        guard let gesture = store.lastGesture else { return }
        if leftPeaks.count < 4 {
            leftPeaks.append(gesture.peakX)
            message = leftPeaks.count >= 4 ? "Now tap the right edge four times." : "Left \(leftPeaks.count) of 4"
        } else if rightPeaks.count < 4 {
            rightPeaks.append(gesture.peakX)
            message = rightPeaks.count >= 4 ? "Ready to save." : "Right \(rightPeaks.count) of 4"
        }
    }
}
