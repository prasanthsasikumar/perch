import Foundation

/// How Perch and the PerchScroll companion talk.
///
/// Changing the direction of every scroll on the Mac takes an active event
/// tap, and the sandbox refuses one: Perch can watch input at most, never
/// alter it. The companion is not sandboxed, holds the Accessibility grant,
/// and runs the tap; Perch is the interface. They share what Tap's two
/// halves share, for the same reasons (`TapLink` has them in full):
///
/// - **The settings file.** Perch writes it in its own container; the
///   companion, inside Perch.app, works out where from Perch's bundle
///   identifier, and only ever reads it.
/// - **Commands**, Perch to companion, as distributed notifications whose
///   object is a short string. The worst a forged one can do is ask for a
///   re-read, a permission prompt, or a quit.
/// - **Status**, companion to Perch, as distributed notifications whose
///   object is JSON. A sandboxed app may receive these but cannot attach a
///   `userInfo` to its own, so both directions use the object.
public enum ScrollLink {
    public static let commandNotification = Notification.Name("org.ahlab.Perch.scroll.command")
    public static let statusNotification = Notification.Name("org.ahlab.Perch.scroll.status")

    public static let companionBundleIdentifier = "org.ahlab.Perch.scroll"
    /// Inside Perch.app.
    public static let companionPath = "Contents/Helpers/PerchScroll.app"
    public static let pluginIdentifier = "org.ahlab.perch.scroll"
    public static let configFilename = "scroll.json"

    /// Scroll Reverser does the same job. Both at once reverse the wheel
    /// twice, which looks like neither is working.
    public static let scrollReverserBundleIdentifier = "com.pilotmoon.scroll-reverser"

    /// Where Accessibility is granted.
    public static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// Overrides for running the companion by hand. Perch cannot pass them:
    /// LaunchServices drops the arguments of an app launched from a sandbox.
    public static let configArgument = "--config"
    public static let parentArgument = "--parent"

    /// Where Perch keeps Scroll's settings, worked out from outside Perch's
    /// sandbox: its container, then the layout `PluginContext.standard` uses
    /// inside it.
    public static func configURL(home: URL, hostBundleIdentifier: String) -> URL {
        home.appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(hostBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/Perch/Plugins", isDirectory: true)
            .appendingPathComponent(pluginIdentifier, isDirectory: true)
            .appendingPathComponent(configFilename)
    }

    /// The Perch.app a companion at `companionURL` lives in.
    public static func hostURL(ofCompanionAt companionURL: URL) -> URL {
        // PerchScroll.app → Helpers → Contents → Perch.app
        companionURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// How often the companion says it is alive, and how long Perch waits
    /// without hearing it before starting another.
    public static let heartbeatInterval: TimeInterval = 1
    public static let heartbeatTimeout: TimeInterval = 6
}

public enum ScrollCommand: String, Equatable, Sendable {
    /// Read the settings file again.
    case reload
    case quit
    /// Ask macOS for Accessibility, which lists PerchScroll in System
    /// Settings, and open that pane.
    case requestAccessibility = "request"

    public var encoded: String { rawValue }

    public init?(encoded: String) {
        self.init(rawValue: encoded)
    }
}

/// What the companion reports, every heartbeat and on every change.
public struct ScrollStatus: Codable, Equatable, Sendable {
    /// `AXIsProcessTrusted()` for the companion. Without it macOS refuses the tap.
    public var isTrusted = false
    /// The event tap exists and is enabled.
    public var isTapActive = false
    /// The kind of device the last scroll came from, while the tap is on.
    public var lastDevice: ScrollDevice?
    /// Whether that scroll was reversed.
    public var lastWasReversed = false
    public var configError: String?
    public var tapError: String?

    public init() {}

    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public init?(encoded: String) {
        guard let value = try? JSONDecoder().decode(ScrollStatus.self, from: Data(encoded.utf8)) else { return nil }
        self = value
    }
}
