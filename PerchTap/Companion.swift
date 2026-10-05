import AppKit
import CoreGraphics
import QuartzCore
import TapKit

/// The engine Perch drives: listens to the sensor, classifies knocks, runs
/// what they map to, and tells Perch what it sees. Main thread, except for
/// the classifier, which has a queue of its own fed at ~800 Hz.
final class Companion {
    private let configURL: URL?
    /// The Perch.app this companion is inside, which it outlives by no more
    /// than a moment.
    private let hostURL: URL
    /// Set only when run by hand with `--parent`.
    private let parentPID: pid_t?

    private var config = TapConfig.default
    private var configError: String?

    private let sensor = SensorManager()
    private let detectorQueue = DispatchQueue(label: "org.ahlab.Perch.tap.detector", qos: .userInteractive)
    private let detector: TapDetector
    private let permissions = Permissions()
    private let sound = TapSound()
    private let hud = HUDController()
    private lazy var executor = ActionExecutor(permissions: permissions, sound: sound)

    private var gestureSequence = 0
    private var lastGesture: DetectedGesture?
    private var lastExecuted: ActionType?
    private var lastActionAt: TimeInterval = 0
    private var stats: GestureStats

    private var liveUntil: Date = .distantPast
    private var heartbeat: Timer?
    private var liveTimer: Timer?
    private var parentWatch: Timer?
    private var lastSentStatus: String?

    private static let statsKey = "stats"

    init(arguments: [String]) {
        let host = TapLink.hostURL(ofCompanionAt: Bundle.main.bundleURL)
        hostURL = host
        let hostID = Bundle(url: host)?.bundleIdentifier
        configURL = Self.value(after: TapLink.configArgument, in: arguments).map { URL(fileURLWithPath: $0) }
            ?? hostID.map { TapLink.configURL(home: Self.realHome, hostBundleIdentifier: $0) }
        parentPID = Self.value(after: TapLink.parentArgument, in: arguments).flatMap { pid_t($0) }
        stats = UserDefaults.standard.data(forKey: Self.statsKey)
            .flatMap { try? JSONDecoder().decode(GestureStats.self, from: $0) } ?? GestureStats()
        detector = TapDetector(
            clock: { CACurrentMediaTime() },
            secondsSinceLastKey: {
                min(
                    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
                    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
                )
            }
        )
    }

    private static var realHome: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    func run() {
        loadConfig()

        detector.onGesture = { [weak self] gesture in
            DispatchQueue.main.async { self?.handle(gesture) }
        }
        sensor.onSample = { [weak self] sample in
            guard let self else { return }
            self.detectorQueue.async { self.detector.process(sample) }
        }
        sensor.onTyping = { [weak self] in
            guard let self else { return }
            self.detectorQueue.async { self.detector.notifyTyping() }
        }
        executor.onBlocked = { [weak self] in
            guard let self, self.permissions.handleBlockedAction() else { return }
            self.hud.flashNeedsAccessibility(layout: self.config.layout)
        }
        permissions.onChange = { [weak self] in self?.sendStatus() }
        permissions.checkAll()
        permissions.startPolling()

        DistributedNotificationCenter.default().addObserver(
            forName: TapLink.commandNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String, let command = TapCommand(encoded: text) else { return }
            self?.perform(command)
        }

        heartbeat = Timer.scheduledTimer(withTimeInterval: TapLink.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendStatus(force: true)
        }
        watchParent()

        // Perch switches a new plugin on for everyone who upgrades, so nothing
        // listens until the user has been through Tap's setup and chosen to.
        if config.enabled && config.hasCompletedOnboarding && config.listening {
            startListening()
        }
        sendStatus(force: true)
    }

    // MARK: - Settings

    private func loadConfig() {
        defer { apply() }
        guard let configURL else {
            configError = "Couldn't find the Perch this is part of"
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            configError = nil
            config = .default
            return
        }
        do {
            config = try JSONDecoder().decode(TapConfig.self, from: Data(contentsOf: configURL))
            configError = nil
        } catch {
            // Keep the last good settings rather than knocking on defaults.
            configError = "Couldn't read Tap's settings: \(error.localizedDescription)"
            NSLog("Perch Tap: %@", configError ?? "")
        }
    }

    private func apply() {
        let config = config
        detectorQueue.async { [detector] in detector.apply(config) }
        sound.apply(config)
    }

    // MARK: - Commands

    private func perform(_ command: TapCommand) {
        switch command {
        case .reload:
            loadConfig()
        case .quit:
            shutDown()
        case .start:
            startListening()
        case .stop:
            sensor.stop()
        case .live:
            liveUntil = Date().addingTimeInterval(TapLink.liveLease)
            startLiveTimer()
        case .request(let kind):
            permissions.request(kind)
        case .openSystemSettings(let kind):
            permissions.openSettings(kind)
        case .previewHUD:
            hud.preview(config: config)
        case .test(let side, let count):
            if let slot = config.slot(side: side, tapCount: count) {
                lastExecuted = slot.actionType
                executor.execute(slot)
            }
        case .simulateArrows(let on):
            let wasRunning = sensor.snapshot().isStreaming
            if wasRunning { sensor.stop() }
            sensor.isArrowSimulationEnabled = on
            if wasRunning || on { startListening() }
        }
        sendStatus()
    }

    private func startListening() {
        apply()
        if !sensor.start() {
            NSLog("Perch Tap: engine not started — this Mac does not expose the motion sensor")
        }
    }

    private func shutDown() {
        sensor.stop()
        sound.stop()
        exit(EXIT_SUCCESS)
    }

    /// Perch starts this companion and expects it gone when Perch is.
    private func watchParent() {
        parentWatch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isHostRunning() {
                NSLog("Perch Tap: Perch is gone, exiting")
                self.shutDown()
            }
        }
    }

    private func isHostRunning() -> Bool {
        if let parentPID {
            return !(kill(parentPID, 0) != 0 && errno == ESRCH)
        }
        let host = hostURL.standardizedFileURL
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleURL?.standardizedFileURL == host && !app.isTerminated
        }
    }

    // MARK: - Knocks

    private func handle(_ gesture: DetectedGesture) {
        gestureSequence += 1
        lastGesture = gesture
        lastExecuted = nil

        stats.record(tapCount: gesture.tapCount)
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.statsKey)
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let slot = config.resolvedSlot(side: gesture.side, tapCount: gesture.tapCount, bundleID: frontApp?.bundleIdentifier)
        if config.showHUD {
            hud.flash(gesture, slot: slot, layout: config.layout)
        }
        if config.soundEnabled {
            sound.playTapSound(side: gesture.side, tapCount: gesture.tapCount)
        }

        defer { sendStatus() }
        guard config.enabled else { return }

        let now = Date().timeIntervalSince1970
        if now - lastActionAt < config.actionCooldown { return }
        lastActionAt = now

        guard let slot, slot.actionType != .none else { return }
        if gesture.isSimulated {
            NSLog("Perch Tap: simulated tap ignored by ActionExecutor")
            return
        }

        lastExecuted = slot.actionType
        DispatchQueue.main.async { [executor] in
            executor.execute(slot, targeting: frontApp)
        }
    }

    // MARK: - Status

    private func startLiveTimer() {
        guard liveTimer == nil else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            if Date() > self.liveUntil {
                timer.invalidate()
                self.liveTimer = nil
                return
            }
            self.sendStatus(force: true)
        }
    }

    private func status() -> TapStatus {
        let snapshot = sensor.snapshot()
        var status = TapStatus()
        status.source = snapshot.source
        status.isStreaming = snapshot.isStreaming
        status.gyroAvailable = snapshot.gyroAvailable
        status.sampleRateHz = snapshot.sampleRateHz
        status.sampleCount = snapshot.sampleCount
        status.lastError = snapshot.lastError
        status.configError = configError
        status.permissions = permissions.state
        status.gestureSequence = gestureSequence
        status.lastGesture = lastGesture
        status.lastExecuted = lastExecuted
        status.stats = stats
        status.arrowSimulation = sensor.isArrowSimulationEnabled

        if Date() <= liveUntil {
            let (noise, pending, reject) = detectorQueue.sync {
                (detector.noiseFloor, detector.pendingTapCount, detector.lastRejectReason)
            }
            let sample = snapshot.lastSample
            status.live = LiveFrame(
                magnitude: LiveFrame.thin(snapshot.magnitude, to: 120),
                x: LiveFrame.thin(snapshot.x, to: 80),
                y: LiveFrame.thin(snapshot.y, to: 80),
                z: LiveFrame.thin(snapshot.z, to: 80),
                sampleX: sample?.x ?? 0,
                sampleY: sample?.y ?? 0,
                sampleZ: sample?.z ?? 0,
                sampleMagnitude: sample?.magnitude ?? 0,
                noiseFloor: noise,
                pendingTapCount: pending,
                lastRejectReason: reject
            )
        }
        return status
    }

    /// Sends when something changed, or always when `force`d by a timer.
    private func sendStatus(force: Bool = false) {
        guard let encoded = status().encoded else { return }
        guard force || encoded != lastSentStatus else { return }
        lastSentStatus = encoded
        DistributedNotificationCenter.default().postNotificationName(
            TapLink.statusNotification, object: encoded, userInfo: nil, deliverImmediately: true
        )
    }
}
