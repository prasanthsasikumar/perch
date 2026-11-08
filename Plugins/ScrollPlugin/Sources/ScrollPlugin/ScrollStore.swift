import AppKit
import Foundation
import Observation
import PerchKit
import ScrollKit

/// Scroll's settings, and what the companion last said.
///
/// Settings are Perch's: kept here, written to the plugin's storage, and
/// re-read by the companion on `.reload`. Whether the tap is running, and
/// whether macOS lets it, comes the other way, in `status`.
@MainActor
@Observable
public final class ScrollStore {
    public enum CompanionState: Equatable {
        case off
        case starting
        case running
        /// Started, but not heard from. Perch keeps trying.
        case notResponding
        case failed(String)
    }

    /// The one line at the top of the panel.
    public enum State: Equatable {
        case starting
        case active
        case needsAccessibility
        case paused
        case helperNotRunning
    }

    public var settings: ScrollSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
        }
    }
    public private(set) var status: ScrollStatus?
    public private(set) var companion: CompanionState = .off
    public private(set) var isScrollReverserRunning = false
    public private(set) var loadFailureNotice: String?
    public private(set) var saveFailureNotice: String?

    @ObservationIgnored private let storage: PluginStorage
    @ObservationIgnored private let link: ScrollCompanionLink
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let runningBundleIdentifiers: () -> [String]
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private var isEnabled = false
    /// The setup is on screen, and needs the companion to ask for and report
    /// Accessibility, though it reverses nothing yet.
    @ObservationIgnored private var isSettingUp = false
    @ObservationIgnored private var isRunningCompanion = false
    @ObservationIgnored private var lastHeard: Date?
    @ObservationIgnored private var lastLaunch: Date?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var ticker: Timer?

    public static let filename = ScrollLink.configFilename

    public init(
        storage: PluginStorage,
        link: ScrollCompanionLink,
        clock: @escaping () -> Date = { .now },
        runningBundleIdentifiers: @escaping () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.storage = storage
        self.link = link
        self.clock = clock
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.openURL = openURL
        do {
            settings = try storage.load(ScrollSettings.self, named: Self.filename) ?? .default
        } catch {
            settings = .default
            loadFailureNotice = "Couldn't read Scroll's settings, so they were reset. A copy was kept as scroll.json.bak."
        }
        link.onStatus = { [weak self] status in self?.receive(status) }
        link.onLaunchFailure = { [weak self] message in
            guard let self, self.isRunningCompanion else { return }
            self.companion = .failed(message)
        }
    }

    public var configURL: URL { storage.url(named: Self.filename) }

    // MARK: - Lifecycle

    /// The companion runs while the plugin is on and set up, or while its
    /// setup is on screen. Never for someone who upgraded and has not looked.
    private var wantsCompanion: Bool {
        isEnabled && (settings.hasCompletedSetup || isSettingUp)
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { refreshConflicts() }
        updateCompanion()
    }

    /// Starts or stops the companion to match `wantsCompanion`.
    private func updateCompanion() {
        if wantsCompanion, !isRunningCompanion {
            isRunningCompanion = true
            saveNow()
            companion = .starting
            launch()
            ticker = Timer.scheduledTimer(withTimeInterval: ScrollLink.heartbeatInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else if !wantsCompanion, isRunningCompanion {
            isRunningCompanion = false
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
        link.launch()
    }

    /// Once a second while the companion should run: restart it if it has
    /// gone quiet, and look for Scroll Reverser.
    func tick() {
        guard isRunningCompanion else { return }
        refreshConflicts()
        let now = clock()
        let timeout = ScrollLink.heartbeatTimeout
        if let lastHeard, now.timeIntervalSince(lastHeard) <= timeout { return }
        if case .failed = companion { return }
        // Give a launch the same grace as a heartbeat before calling it lost.
        if let lastLaunch, now.timeIntervalSince(lastLaunch) <= timeout { return }
        companion = .notResponding
        launch()
    }

    /// After a failure the user asked to try again.
    public func retry() {
        guard isRunningCompanion else {
            updateCompanion()
            return
        }
        companion = .starting
        launch()
    }

    func receive(_ newStatus: ScrollStatus) {
        guard isRunningCompanion else { return }
        lastHeard = clock()
        companion = .running
        status = newStatus
    }

    // MARK: - Setup

    /// The setup appeared: start the companion so it can ask for
    /// Accessibility and say when it has it. It stays up if the panel closes,
    /// which it does the moment System Settings comes forward; with no tap
    /// installed it does nothing but answer.
    public func beginSetup() {
        isSettingUp = true
        updateCompanion()
    }

    public func completeSetup() {
        settings.hasCompletedSetup = true
        isSettingUp = false
        saveNow()
        updateCompanion()
    }

    public func replaySetup() {
        settings.hasCompletedSetup = false
        saveNow()
    }

    /// The companion asks, so that PerchScroll, the process that needs it, is
    /// what System Settings lists. If it is not running, Perch opens the pane.
    public func requestAccessibility() {
        if companion == .running {
            link.send(.requestAccessibility)
        } else {
            openURL(ScrollLink.accessibilitySettingsURL)
        }
    }

    // MARK: - Scroll Reverser

    public func refreshConflicts() {
        let running = runningBundleIdentifiers().contains(ScrollLink.scrollReverserBundleIdentifier)
        if running != isScrollReverserRunning { isScrollReverserRunning = running }
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
            try storage.save(settings, named: Self.filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save Scroll's settings: \(error.localizedDescription)"
            return
        }
        if isRunningCompanion { link.send(.reload) }
    }

    // MARK: - Derived

    public var isTrusted: Bool { status?.isTrusted ?? false }

    public var state: State {
        switch companion {
        case .off, .failed, .notResponding:
            return .helperNotRunning
        case .starting:
            return .starting
        case .running:
            guard let status else { return .starting }
            if !status.isTrusted { return .needsAccessibility }
            if !settings.isReversing { return .paused }
            return status.isTapActive ? .active : .starting
        }
    }
}
