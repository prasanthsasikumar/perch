import AppKit
import ApplicationServices
import ScrollKit

/// The engine Perch drives: holds the event tap while the settings and
/// Accessibility allow it, and tells Perch where things stand. Main thread.
final class Companion {
    private let configURL: URL?
    /// The Perch.app this companion is inside, which it outlives by no more
    /// than a moment.
    private let hostURL: URL
    /// Set only when run by hand with `--parent`.
    private let parentPID: pid_t?

    private var settings = ScrollSettings.default
    private var configError: String?
    private var tapError: String?
    private var isTrusted = false

    private let tap = ScrollTap()
    private var heartbeat: Timer?
    private var parentWatch: Timer?
    private var lastSentStatus: String?

    init(arguments: [String]) {
        let host = ScrollLink.hostURL(ofCompanionAt: Bundle.main.bundleURL)
        hostURL = host
        let hostID = Bundle(url: host)?.bundleIdentifier
        configURL = Self.value(after: ScrollLink.configArgument, in: arguments).map { URL(fileURLWithPath: $0) }
            ?? hostID.map { ScrollLink.configURL(home: Self.realHome, hostBundleIdentifier: $0) }
        parentPID = Self.value(after: ScrollLink.parentArgument, in: arguments).flatMap { pid_t($0) }
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
        loadSettings()

        DistributedNotificationCenter.default().addObserver(
            forName: ScrollLink.commandNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String, let command = ScrollCommand(encoded: text) else { return }
            self?.perform(command)
        }

        // Also how a grant made in System Settings is noticed: there is no
        // notification for it, so trust is re-checked every beat.
        heartbeat = Timer.scheduledTimer(withTimeInterval: ScrollLink.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.update()
            self?.sendStatus(force: true)
        }
        watchParent()

        update()
        sendStatus(force: true)
    }

    // MARK: - Settings

    private func loadSettings() {
        defer { update() }
        guard let configURL else {
            configError = "Couldn't find the Perch this is part of"
            return
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            configError = nil
            settings = .default
            return
        }
        do {
            settings = try JSONDecoder().decode(ScrollSettings.self, from: Data(contentsOf: configURL))
            configError = nil
        } catch {
            // Keep the last good settings rather than flip the wheel back.
            configError = "Couldn't read Scroll's settings: \(error.localizedDescription)"
            NSLog("Perch Scroll: %@", configError ?? "")
        }
    }

    /// Installs the tap when there is something to reverse and macOS allows
    /// it, and removes it otherwise, so a paused Scroll touches no scrolls.
    private func update() {
        isTrusted = AXIsProcessTrusted()
        tap.settings = settings
        guard settings.isReversing, isTrusted else {
            tap.stop()
            tapError = nil
            return
        }
        if tap.start() {
            tap.reenable()
            tapError = nil
        } else {
            tapError = "macOS refused PerchScroll's scroll tap. In Accessibility, turn PerchScroll off and on again."
        }
    }

    // MARK: - Commands

    private func perform(_ command: ScrollCommand) {
        switch command {
        case .reload:
            loadSettings()
        case .quit:
            shutDown()
        case .requestAccessibility:
            requestAccessibility()
        }
        sendStatus()
    }

    /// The prompt adds PerchScroll to the list in System Settings, switched
    /// off; the pane is opened so the switch is right there.
    private func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if isTrusted {
            update()
            return
        }
        NSWorkspace.shared.open(ScrollLink.accessibilitySettingsURL)
    }

    private func shutDown() {
        tap.stop()
        exit(EXIT_SUCCESS)
    }

    /// Perch starts this companion and expects it gone when Perch is.
    private func watchParent() {
        parentWatch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isHostRunning() {
                NSLog("Perch Scroll: Perch is gone, exiting")
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

    // MARK: - Status

    private func status() -> ScrollStatus {
        var status = ScrollStatus()
        status.isTrusted = isTrusted
        status.isTapActive = tap.isActive
        status.lastDevice = tap.lastDevice
        status.lastWasReversed = tap.lastWasReversed
        status.configError = configError
        status.tapError = tapError
        return status
    }

    /// Sends when something changed, or always when `force`d by the heartbeat.
    private func sendStatus(force: Bool = false) {
        guard let encoded = status().encoded else { return }
        guard force || encoded != lastSentStatus else { return }
        lastSentStatus = encoded
        DistributedNotificationCenter.default().postNotificationName(
            ScrollLink.statusNotification, object: encoded, userInfo: nil, deliverImmediately: true
        )
    }
}
