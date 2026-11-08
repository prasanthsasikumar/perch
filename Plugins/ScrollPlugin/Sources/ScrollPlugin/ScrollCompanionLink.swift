import AppKit
import Foundation
import ScrollKit

/// Starts the PerchScroll companion and carries messages to and from it.
/// A protocol so the store can be tested without a second process.
@MainActor
public protocol ScrollCompanionLink: AnyObject {
    /// Called with every status the companion sends.
    var onStatus: ((ScrollStatus) -> Void)? { get set }
    /// Called if the companion could not be started.
    var onLaunchFailure: ((String) -> Void)? { get set }
    func launch()
    func send(_ command: ScrollCommand)
}

/// The real thing: the companion inside Perch.app, and distributed
/// notifications. See `ScrollLink` for why it is built this way.
@MainActor
public final class LiveScrollCompanionLink: ScrollCompanionLink {
    public var onStatus: ((ScrollStatus) -> Void)?
    public var onLaunchFailure: ((String) -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: ScrollLink.statusNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String, let status = ScrollStatus(encoded: text) else { return }
            MainActor.assumeIsolated { self?.onStatus?(status) }
        }
    }

    public func launch() {
        let companion = Bundle.main.bundleURL.appending(path: ScrollLink.companionPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: companion.path) else {
            onLaunchFailure?("PerchScroll is missing from Perch.app. Reinstall Perch.")
            return
        }
        // No arguments: LaunchServices drops them for a sandboxed caller.
        // The companion finds the settings and this Perch from where it lives.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: companion, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onLaunchFailure?(message) }
            }
        }
    }

    public func send(_ command: ScrollCommand) {
        DistributedNotificationCenter.default().postNotificationName(
            ScrollLink.commandNotification, object: command.encoded, userInfo: nil, deliverImmediately: true
        )
    }
}
