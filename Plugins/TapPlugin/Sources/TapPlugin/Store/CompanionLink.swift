import AppKit
import Foundation
import TapKit

/// Starts the PerchTap companion and carries messages to and from it.
/// A protocol so the store can be tested without a second process.
@MainActor
public protocol CompanionLink: AnyObject {
    /// Called with every status the companion sends.
    var onStatus: ((TapStatus) -> Void)? { get set }
    /// Called if the companion could not be started.
    var onLaunchFailure: ((String) -> Void)? { get set }
    /// Starts the companion, which will read the settings at `configURL`.
    func launch(configURL: URL)
    func send(_ command: TapCommand)
}

/// The real thing: the companion inside Perch.app, and distributed
/// notifications. See `TapLink` for why it is built this way.
@MainActor
public final class LiveCompanionLink: CompanionLink {
    public var onStatus: ((TapStatus) -> Void)?
    public var onLaunchFailure: ((String) -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: TapLink.statusNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String, let status = TapStatus(encoded: text) else { return }
            MainActor.assumeIsolated { self?.onStatus?(status) }
        }
    }

    public func launch(configURL: URL) {
        let companion = Bundle.main.bundleURL.appending(path: TapLink.companionPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: companion.path) else {
            onLaunchFailure?("PerchTap is missing from Perch.app. Reinstall Perch.")
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

    public func send(_ command: TapCommand) {
        DistributedNotificationCenter.default().postNotificationName(
            TapLink.commandNotification, object: command.encoded, userInfo: nil, deliverImmediately: true
        )
    }
}
