import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
import TapKit

/// The companion's own grants. They are its, not Perch's: it is the process
/// that types, so it is the one listed in Privacy & Security.
///
/// Required:
///   - Accessibility (CGEvent posting — keyboard shortcuts, media keys, lock screen)
/// Optional:
///   - Input Monitoring (ignore-while-typing)
///   - Automation of System Events (most shortcuts are typed through it)
///
/// Ported from MacTap. Main thread only.
final class Permissions {
    private(set) var state = TapPermissions()
    var onChange: (() -> Void)?

    private var pollTimer: Timer?
    private var lastBlockedPromptAt: TimeInterval = 0

    func checkAll() {
        let before = state
        state.accessibility = AXIsProcessTrusted() ? .granted : .notDetermined
        state.postEvent = CGPreflightPostEventAccess() ? .granted : .notDetermined
        state.inputMonitoring = switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
        if state.appleEvents == .unknown {
            state.appleEvents = .notDetermined
        }
        if state != before { onChange?() }
    }

    /// Re-checks every so often, so a grant made in System Settings shows
    /// up without a relaunch.
    func startPolling(interval: TimeInterval = 1.5) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkAll()
        }
    }

    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility: requestAccessibility()
        case .inputMonitoring: requestInputMonitoring()
        case .automation: requestAppleEvents()
        }
    }

    func openSettings(_ kind: PermissionKind) {
        switch kind {
        case .accessibility: openSystemSettings(section: "Privacy_Accessibility")
        case .inputMonitoring: openSystemSettings(section: "Privacy_ListenEvent")
        case .automation: openSystemSettings(section: "Privacy_Automation")
        }
    }

    private func requestAccessibility() {
        NSLog("Perch Tap: requesting Accessibility + Post Event")
        // Post Event is a separate TCC service. Tahoe drops Command-chords
        // unless this grant is actually present, even if Accessibility looks on.
        _ = CGRequestPostEventAccess()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        checkAll()
        if state.canPostEvents { return }
        openSettings(.accessibility)
        startPolling(interval: 0.6)
    }

    /// Called when a knock tried to send a shortcut without Accessibility.
    /// Returns whether it prompted, at most once every few seconds.
    @discardableResult
    func handleBlockedAction() -> Bool {
        let now = Date().timeIntervalSince1970
        guard now - lastBlockedPromptAt > 4 else { return false }
        lastBlockedPromptAt = now
        requestAccessibility()
        return true
    }

    private func requestInputMonitoring() {
        NSLog("Perch Tap: requesting Input Monitoring")
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSettings(.inputMonitoring)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAll()
        }
    }

    /// There is no way to ask about Automation without trying it, so this
    /// tries the cheapest thing System Events will do.
    func requestAppleEvents(openSettings shouldOpen: Bool = true) {
        NSLog("Perch Tap: requesting Automation of System Events")
        if shouldOpen { openSettings(.automation) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errorInfo: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to return")?.executeAndReturnError(&errorInfo)
            let number = errorInfo?[NSAppleScript.errorNumber] as? Int
            DispatchQueue.main.async {
                self?.recordAppleEvents(errorNumber: number)
            }
        }
    }

    /// -1743 is "not authorized", -1708 what an unapproved app gets back.
    func recordAppleEvents(errorNumber: Int?) {
        let before = state.appleEvents
        if let number = errorNumber, number == -1743 || number == -1708 {
            state.appleEvents = .denied
        } else if errorNumber == nil || errorNumber == 0 {
            state.appleEvents = .granted
        }
        if state.appleEvents != before { onChange?() }
    }

    private func openSystemSettings(section: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(section)",
            "x-apple.systempreferences:com.apple.preference.security?\(section)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for spec in candidates {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
