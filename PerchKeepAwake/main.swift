import AppKit
import ServiceManagement

/// Registers Perch's root helper, then quits.
///
/// This exists because Perch is sandboxed, and the sandbox refuses to let an
/// app register a daemon. This companion is not sandboxed, owns the helper
/// and its launchd job, and is launched by Perch when the keep-awake toggle
/// finds the helper unreachable. It takes no input of any kind.

let service = SMAppService.daemon(plistName: SleepHelper.daemonPlistName)

func registration() -> CompanionPlan.Registration {
    switch service.status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notRegistered, .notFound: .notRegistered
    @unknown default: .notRegistered
    }
}

var failure: Error?
if CompanionPlan.shouldRegister(registration()) {
    do {
        try service.register()
    } catch {
        // `register()` also throws while approval is pending; the status
        // below tells the two apart.
        failure = error
    }
}

let outcome = CompanionPlan.outcome(for: registration())
if let message = outcome.message {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Keep Awake needs your attention"
    alert.informativeText = [message, failure?.localizedDescription]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    alert.addButton(withTitle: "Open Login Items")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { exit(EXIT_SUCCESS) }
}
SMAppService.openSystemSettingsLoginItems()
