import AppKit
import SwiftUI

/// Owns the welcome window: opens it on a fresh install, again on request
/// from Settings, and hands the user to the panel when they finish.
///
/// An `NSWindow` rather than a SwiftUI `Window` scene: Perch is a menu bar
/// app with no main window, and a scene cannot be opened from `App.init`
/// before any view exists to call `openWindow`.
@MainActor
final class WelcomeCoordinator: NSObject, NSWindowDelegate {
    private let registry: PluginRegistry
    private let appState: AppState
    private var window: NSWindow?

    init(registry: PluginRegistry, appState: AppState) {
        self.registry = registry
        self.appState = appState
    }

    /// Opens the welcome window on a fresh install; a no-op otherwise.
    /// Launching with `-PerchShowWelcome YES` opens it regardless, for
    /// trying it out without wiping an install's settings.
    func presentIfNeeded() {
        if registry.needsWelcome || UserDefaults.standard.bool(forKey: "PerchShowWelcome") {
            present()
        }
    }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = WelcomeView(registry: registry) { [weak self] openPanel in
            self?.finish(openPanel: openPanel)
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Perch"
        window.setContentSize(WelcomeView.size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        // Perch is LSUIElement, so without this the window opens behind
        // whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(openPanel: Bool) {
        registry.needsWelcome = false
        window?.close()
        guard openPanel else { return }
        // After the window is gone, so the panel is not dismissed by the
        // focus change that closing it causes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [appState] in
            appState.isMenuPresented = true
        }
    }

    /// Closing the window with its close button keeps whatever is enabled and
    /// counts as finished: asking again at every launch would be nagging, and
    /// Settings can always reopen it.
    func windowWillClose(_ notification: Notification) {
        registry.needsWelcome = false
        window = nil
    }
}
