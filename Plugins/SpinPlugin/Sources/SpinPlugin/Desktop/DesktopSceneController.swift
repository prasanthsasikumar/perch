import AppKit
import SwiftUI

/// Owns the desktop-level window. It exists only while the model wants it,
/// and fades in and out rather than popping.
@MainActor
final class DesktopSceneController {
    private let model: SpinModel
    private var window: NSWindow?
    private var screenToken: NSObjectProtocol?
    private var generation = 0
    private var shownSceneID: String?
    private var backgrounds: [String: NSImage] = [:]
    private var running = false

    init(model: SpinModel) {
        self.model = model
    }

    func start() {
        running = true
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        observe()
    }

    func stop() {
        running = false
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        screenToken = nil
        window?.orderOut(nil)
        window = nil
        shownSceneID = nil
    }

    private func observe() {
        guard running else { return }
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update() {
        if model.wantsWindow, let scene = model.selectedScene { show(scene) } else { hide() }
    }

    private func background(for scene: SceneAsset) -> NSImage? {
        if let cached = backgrounds[scene.id] { return cached }
        let image = NSImage(contentsOf: scene.backgroundURL)
        backgrounds[scene.id] = image
        return image
    }

    private func show(_ scene: SceneAsset) {
        guard let screen = NSScreen.screens.first, let background = background(for: scene) else { return }
        generation += 1
        // update() re-runs on every phase change; only rebuild the view for a new scene.
        let content = { NSHostingView(rootView: SceneView(model: self.model, background: background)) }
        if let window {
            if shownSceneID != scene.id { window.contentView = content() }
        } else {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            // Just above the wallpaper, below the desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = content()
            window.orderFront(nil)
            self.window = window
        }
        shownSceneID = scene.id
        window?.setFrame(screen.frame, display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            window?.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let window else { return }
        generation += 1
        let fading = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() during the fade bumped the generation; keep the window.
                guard let self, self.generation == fading else { return }
                self.window?.orderOut(nil)
                self.window = nil
                self.shownSceneID = nil
            }
        }
    }

    /// Refits a visible scene, and brings up one that could not be shown
    /// while no display was attached (clamshell, a monitor reconnecting).
    private func screensChanged() {
        guard let window else {
            update()
            return
        }
        guard let screen = NSScreen.screens.first else { return }
        window.setFrame(screen.frame, display: true)
    }
}
