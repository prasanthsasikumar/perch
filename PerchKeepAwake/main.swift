import AppKit
import ServiceManagement

/// Registers Perch's root helper, then quits.
///
/// This exists because Perch is sandboxed, and the sandbox refuses to let an
/// app register a daemon. This companion is not sandboxed, owns the helper
/// and its launchd job, and is launched by Perch the first time the
/// keep-awake toggle finds the helper unreachable.

let service = SMAppService.daemon(plistName: SleepHelper.daemonPlistName)

var failure: Error?
if service.status != .enabled {
    do {
        try service.register()
    } catch {
        // `register()` also throws while approval is pending; the status
        // below tells the two apart.
        failure = error
    }
}

switch service.status {
case .enabled:
    break
case .requiresApproval:
    SMAppService.openSystemSettingsLoginItems()
default:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Perch could not set up Keep Awake"
    alert.informativeText = failure?.localizedDescription
        ?? "The helper could not be registered."
    alert.runModal()
}
