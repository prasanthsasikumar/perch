import AppKit
import Foundation
import Observation
import PerchKit
import TapKit

/// Tap's settings, and what the companion last said.
///
/// Settings are Perch's: kept here, written to the plugin's storage, and
/// re-read by the companion on `.reload`. Everything about the sensor and the
/// knocks comes the other way, in `status`.
@MainActor
@Observable
public final class TapStore {
    public enum CompanionState: Equatable {
        case off
        case starting
        case running
        /// Started, but not heard from. Perch keeps trying.
        case notResponding
        case failed(String)
    }

    public var config: TapConfig {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
        }
    }
    public private(set) var status: TapStatus?
    public private(set) var companion: CompanionState = .off
    /// Goes up once for every knock the companion reports.
    public private(set) var gestureToken = 0
    public private(set) var loadFailureNotice: String?
    public private(set) var saveFailureNotice: String?

    @ObservationIgnored private let storage: PluginStorage
    @ObservationIgnored private let link: CompanionLink
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var lastHeard: Date?
    @ObservationIgnored private var lastLaunch: Date?
    @ObservationIgnored private var liveViewers = 0
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private lazy var previewSound = TapSound()

    public static let filename = TapLink.configFilename

    public init(storage: PluginStorage, link: CompanionLink, clock: @escaping () -> Date = { .now }) {
        self.storage = storage
        self.link = link
        self.clock = clock
        do {
            config = try storage.load(TapConfig.self, named: Self.filename) ?? .default
        } catch {
            config = .default
            loadFailureNotice = "Couldn't read Tap's settings, so they were reset. A copy was kept as tap.json.bak."
        }
        link.onStatus = { [weak self] status in self?.receive(status) }
        link.onLaunchFailure = { [weak self] message in
            guard let self, self.isEnabled else { return }
            self.companion = .failed(message)
        }
    }

    public var configURL: URL { storage.url(named: Self.filename) }

    // MARK: - Lifecycle

    /// On: write the settings, start the companion, and keep it running.
    /// Off: tell it to quit.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            saveNow()
            companion = .starting
            launch()
            ticker = Timer.scheduledTimer(withTimeInterval: TapLink.heartbeatInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else {
            ticker?.invalidate()
            ticker = nil
            link.send(.quit)
            companion = .off
            status = nil
            lastHeard = nil
        }
    }

    private func launch() {
        lastLaunch = clock()
        link.launch(configURL: configURL)
    }

    /// Once a second while enabled: renew the live lease for any view that
    /// shows sensor data, and restart a companion that has gone quiet.
    func tick() {
        guard isEnabled else { return }
        if liveViewers > 0 { link.send(.live) }

        let now = clock()
        let timeout = TapLink.heartbeatTimeout
        if let lastHeard, now.timeIntervalSince(lastHeard) <= timeout { return }
        if case .failed = companion { return }
        // Give a launch the same grace as a heartbeat before calling it lost.
        if let lastLaunch, now.timeIntervalSince(lastLaunch) <= timeout { return }
        companion = .notResponding
        launch()
    }

    /// After a failure the user asked to try again.
    public func retry() {
        guard isEnabled else { return }
        companion = .starting
        launch()
    }

    func receive(_ newStatus: TapStatus) {
        guard isEnabled else { return }
        lastHeard = clock()
        companion = .running
        if newStatus.gestureSequence != status?.gestureSequence, newStatus.lastGesture != nil {
            gestureToken &+= 1
        }
        // Live data only arrives while someone is watching; keep the last
        // frame rather than flickering to nothing between heartbeats.
        var merged = newStatus
        if merged.live == nil, liveViewers > 0 { merged.live = status?.live }
        status = merged
    }

    // MARK: - Live sensor data

    /// A view that shows the waveform calls this on appear…
    public func beginLive() {
        liveViewers += 1
        if liveViewers == 1, isEnabled { link.send(.live) }
    }

    /// …and this on disappear.
    public func endLive() {
        liveViewers = max(0, liveViewers - 1)
    }

    // MARK: - Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try storage.save(config, named: Self.filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save Tap's settings: \(error.localizedDescription)"
            return
        }
        if isEnabled { link.send(.reload) }
    }

    // MARK: - Derived

    public var isListening: Bool { status?.isStreaming ?? false }
    public var isSensorAvailable: Bool { status?.isSensorAvailable ?? true }
    public var permissions: TapPermissions { status?.permissions ?? TapPermissions() }
    public var lastGesture: DetectedGesture? { status?.lastGesture }
    public var todayCount: Int { status?.stats.today() ?? 0 }

    public func slots(for side: TapSide) -> [GestureSlot] {
        config.slots.filter { $0.side == side }.sorted { $0.tapCount < $1.tapCount }
    }

    // MARK: - Commands

    /// Saved before the companion is told, so a pause outlasts a restart.
    public func setListening(_ on: Bool) {
        config.listening = on
        saveNow()
        link.send(on ? .start : .stop)
    }
    public func request(_ kind: PermissionKind) { link.send(.request(kind)) }
    public func openSystemSettings(_ kind: PermissionKind) { link.send(.openSystemSettings(kind)) }
    public func previewHUD() { link.send(.previewHUD) }
    public func simulateArrows(_ on: Bool) { link.send(.simulateArrows(on)) }

    /// Runs a cell of the map now. Saved first, so what runs is what is shown.
    public func test(_ slot: GestureSlot) {
        saveNow()
        link.send(.test(slot.side, slot.tapCount))
    }

    // MARK: - Editing

    public func applyPreset(_ preset: GesturePreset) {
        config.applyPreset(preset)
    }

    public func updateSlot(_ slot: GestureSlot) {
        guard let index = config.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        config.slots[index] = slot
    }

    /// Adds a rule for an app, or returns the one it already has.
    @discardableResult
    public func addRule(bundleID: String, appName: String) -> UUID {
        if let existing = config.appRules.first(where: { $0.bundleID == bundleID }) {
            return existing.id
        }
        let rule = AppRule(bundleID: bundleID, appName: appName)
        config.appRules.append(rule)
        return rule.id
    }

    public func removeRule(_ id: UUID) {
        config.appRules.removeAll { $0.id == id }
    }

    /// Sets or clears (`nil`: inherit) one cell of an app's overrides.
    public func setOverride(_ action: ActionType?, side: TapSide, tapCount: Int, inRule id: UUID) {
        guard let index = config.appRules.firstIndex(where: { $0.id == id }) else { return }
        config.appRules[index].slots.removeAll { $0.side == side && $0.tapCount == tapCount }
        if let action {
            config.appRules[index].slots.append(GestureSlot(side: side, tapCount: tapCount, actionType: action))
        }
    }

    public func resetSettings() {
        config = config.reset()
    }

    /// Clears the old correction so the samples are raw, and makes sure the
    /// sensor is on to take them.
    public func beginCalibration() {
        config.invertSides = false
        config.sideBias = 0
        saveNow()
        if !isListening { setListening(true) }
    }

    /// Returns whether the sides were swapped.
    @discardableResult
    public func commitCalibration(leftPeaks: [Double], rightPeaks: [Double]) -> Bool? {
        guard let result = TapConfig.calibration(leftPeaks: leftPeaks, rightPeaks: rightPeaks) else { return nil }
        config.invertSides = result.invertSides
        config.sideBias = result.sideBias
        return result.invertSides
    }

    public func completeOnboarding() {
        config.hasCompletedOnboarding = true
        if !isListening { setListening(true) }
    }

    public func replayOnboarding() {
        config.hasCompletedOnboarding = false
    }

    // MARK: - Sound preview

    /// Plays in Perch, so a pack can be heard before it is chosen.
    public func preview(sound name: String) {
        previewSound.pack = config.soundPack
        previewSound.volume = config.soundVolume
        previewSound.playSound(name)
    }
}
