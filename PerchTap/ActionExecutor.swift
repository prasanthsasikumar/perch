import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import TapKit

/// Runs what a knock is mapped to. Ported from MacTap.
///
/// Nearly everything here is something Perch's sandbox refuses: posting
/// keystrokes into other apps, scripting System Events, running the user's
/// shell commands. That is the second reason this companion exists.
final class ActionExecutor {
    private let permissions: Permissions
    private let sound: TapSound
    /// A knock tried to type without Accessibility.
    var onBlocked: (() -> Void)?

    private var targetPID: pid_t = 0

    init(permissions: Permissions, sound: TapSound) {
        self.permissions = permissions
        self.sound = sound
    }

    func execute(_ slot: GestureSlot, targeting app: NSRunningApplication? = nil) {
        if Thread.isMainThread {
            perform(slot, targeting: app)
        } else {
            DispatchQueue.main.async { self.perform(slot, targeting: app) }
        }
    }

    private func perform(_ slot: GestureSlot, targeting app: NSRunningApplication?) {
        NSLog("Perch Tap: execute %@ for %@ × %d", slot.actionType.displayName, slot.side.rawValue, slot.tapCount)

        targetPID = pid_t(app?.processIdentifier ?? 0)
        if slot.actionType.needsAccessibility {
            activate(app)
        }

        switch slot.actionType {
        case .none: break
        case .copy: sendKeyboardShortcut("cmd+c")
        case .paste: sendKeyboardShortcut("cmd+v")
        case .cut: sendKeyboardShortcut("cmd+x")
        case .undo: sendKeyboardShortcut("cmd+z")
        case .redo: sendKeyboardShortcut("cmd+shift+z")
        case .save: sendKeyboardShortcut("cmd+s")
        case .selectAll: sendKeyboardShortcut("cmd+a")
        case .aiAccept: sendKey(KeyChord(keyCode: UInt16(kVK_Return)))
        case .aiReject: sendKey(KeyChord(keyCode: UInt16(kVK_Escape)))
        case .newTab: sendKeyboardShortcut("cmd+t")
        case .closeTab: sendKeyboardShortcut("cmd+w")
        case .shellCommand: runShell(slot.parameter)
        case .appleScript: runAppleScript(slot.parameter)
        case .openURL: openURL(slot.parameter)
        case .openApp: openApp(slot.parameter)
        case .runShortcut: runShortcut(slot.parameter)
        case .keyboardShortcut: sendKeyboardShortcut(slot.parameter)
        case .mediaPlayPause: postSystemKey(NX_KEYTYPE_PLAY)
        case .mediaNext: postSystemKey(NX_KEYTYPE_NEXT)
        case .mediaPrevious: postSystemKey(NX_KEYTYPE_PREVIOUS)
        case .mute: postSystemKey(NX_KEYTYPE_MUTE)
        case .volumeUp: postSystemKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: postSystemKey(NX_KEYTYPE_SOUND_DOWN)
        case .screenshot: sendKeyboardShortcut("cmd+shift+3")
        case .screenshotSelection: sendKeyboardShortcut("cmd+shift+4")
        case .lockScreen: lockScreen()
        case .sleepDisplay: sleepDisplay()
        case .startScreensaver: startScreensaver()
        case .missionControl: openMissionControl()
        case .spotlight: sendKeyboardShortcut("cmd+space")
        case .showDesktop: showDesktop()
        case .notificationCenter: openNotificationCenter()
        case .hideFrontApp: sendKeyboardShortcut("cmd+h")
        case .hideOthers: sendKeyboardShortcut("cmd+opt+h")
        case .switchDesktopLeft: sendKeyboardShortcut("ctrl+left")
        case .switchDesktopRight: sendKeyboardShortcut("ctrl+right")
        case .tileLeft: sendKeyboardShortcut("fn+ctrl+left")
        case .tileRight: sendKeyboardShortcut("fn+ctrl+right")
        case .toggleDarkMode: toggleDarkMode()
        case .dictation: startDictation()
        case .soundFX: sound.playTapSound(side: slot.side, tapCount: slot.tapCount)
        }
    }

    // MARK: - Shell / AppleScript / URL / App

    private func runShell(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", trimmed]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            NSLog("Perch Tap: shell failed: %@", error.localizedDescription)
        }
    }

    private func runAppleScript(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: trimmed)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                NSLog("Perch Tap: AppleScript error: %@", String(describing: errorInfo))
            }
        }
    }

    private func openURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleaned = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: cleaned) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openApp(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        if trimmed.contains("."),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }

        if let url = applicationURL(named: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    NSLog("Perch Tap: openApplication failed: %@", error.localizedDescription)
                    self.runShell("open -a \(Self.shellQuote(trimmed))")
                }
            }
            return
        }

        runShell("open -a \(Self.shellQuote(trimmed))")
    }

    private func activate(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated, app != NSRunningApplication.current else { return }
        app.activate()
        usleep(35_000)
    }

    private func runShortcut(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", trimmed]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            NSLog("Perch Tap: shortcuts run failed: %@", error.localizedDescription)
        }
    }

    private func startDictation() {
        sendKey(KeyChord(keyCode: UInt16(kVK_Function)))
        usleep(90_000)
        sendKey(KeyChord(keyCode: UInt16(kVK_Function)))
    }

    private func applicationURL(named name: String) -> URL? {
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
        for root in roots {
            let candidate = root.appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - System actions

    private func lockScreen() {
        sendKeyboardShortcut("ctrl+cmd+q")
        runAppleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
    }

    private func sleepDisplay() {
        runShell("pmset displaysleepnow")
    }

    private func startScreensaver() {
        let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        if FileManager.default.fileExists(atPath: engine.path) {
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
        } else {
            runAppleScript("tell application \"System Events\" to start current screen saver")
        }
    }

    private func openMissionControl() {
        let paths = [
            "/System/Applications/Mission Control.app",
            "/System/Library/CoreServices/Mission Control.app",
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        sendKeyboardShortcut("ctrl+up")
    }

    private func showDesktop() {
        sendKey(KeyChord(keyCode: UInt16(kVK_F11)))
        runAppleScript("tell application \"System Events\" to key code 103")
    }

    private func openNotificationCenter() {
        runAppleScript("""
        tell application "System Events"
            try
                tell application process "ControlCenter"
                    set candidates to menu bar items of menu bar 1
                    repeat with itemRef in candidates
                        set desc to description of itemRef
                        if desc contains "Notification" or desc contains "Date" or desc contains "Clock" or desc contains "Control Center" then
                            click itemRef
                            return
                        end if
                    end repeat
                    if (count of candidates) > 0 then click last item of candidates
                end tell
            end try
            try
                tell application process "Control Center"
                    click last menu bar item of menu bar 1
                end tell
            end try
        end tell
        """)
    }

    private func toggleDarkMode() {
        runAppleScript("""
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """)
    }

    // MARK: - Keyboard

    private func sendKeyboardShortcut(_ shortcut: String) {
        guard let chord = KeyChord(parsing: shortcut) else {
            NSLog("Perch Tap: could not parse shortcut: %@", shortcut)
            return
        }
        sendKey(chord)
    }

    /// On macOS 26, CGEvent Command-chords from ad-hoc binaries are often
    /// dropped even when Accessibility looks granted. System Events is the
    /// path that still reaches Spotlight, copy, paste, and app shortcuts.
    private func sendKey(_ chord: KeyChord) {
        if sendViaSystemEvents(chord) {
            return
        }
        sendViaCGEvent(chord)
        if !CGPreflightPostEventAccess() && !AXIsProcessTrusted() {
            onBlocked?()
        }
    }

    @discardableResult
    private func sendViaSystemEvents(_ chord: KeyChord) -> Bool {
        var parts: [String] = []
        if chord.modifiers.contains(.command) { parts.append("command down") }
        if chord.modifiers.contains(.shift) { parts.append("shift down") }
        if chord.modifiers.contains(.option) { parts.append("option down") }
        if chord.modifiers.contains(.control) { parts.append("control down") }
        let using = parts.isEmpty ? "" : " using {\(parts.joined(separator: ", "))}"
        let source = "tell application \"System Events\" to key code \(Int(chord.keyCode))\(using)"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo, let number = errorInfo[NSAppleScript.errorNumber] as? Int, number != 0 {
            NSLog("Perch Tap: System Events key code %d failed (%d)", Int(chord.keyCode), number)
            permissions.recordAppleEvents(errorNumber: number)
            if number == -1743 || number == -1708 {
                permissions.requestAppleEvents()
            }
            return false
        }
        permissions.recordAppleEvents(errorNumber: nil)
        return true
    }

    private func sendViaCGEvent(_ chord: KeyChord) {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        guard let source = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState) else { return }
        source.localEventsSuppressionInterval = 0
        let flags = cgFlags(from: chord.modifiers)
        let pid = targetPID

        func post(down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            event.post(tap: .cgSessionEventTap)
            if pid > 0 {
                event.postToPid(pid)
            }
        }

        post(down: true)
        usleep(16_000)
        post(down: false)
    }

    private func cgFlags(from modifiers: KeyChord.Modifiers) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    // NX_KEYTYPE_* from IOKit / HIToolbox
    private let NX_KEYTYPE_SOUND_UP = 0
    private let NX_KEYTYPE_SOUND_DOWN = 1
    private let NX_KEYTYPE_MUTE = 7
    private let NX_KEYTYPE_PLAY = 16
    private let NX_KEYTYPE_NEXT = 17
    private let NX_KEYTYPE_PREVIOUS = 18

    private func postSystemKey(_ key: Int) {
        pulseSystemKey(key, down: true)
        usleep(40_000)
        pulseSystemKey(key, down: false)
    }

    private func pulseSystemKey(_ key: Int, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = (key << 16) | (down ? 0xA00 : 0xB00)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
