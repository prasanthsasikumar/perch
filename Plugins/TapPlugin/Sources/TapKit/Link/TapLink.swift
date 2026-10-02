import Foundation

/// How Perch and the PerchTap companion talk.
///
/// Perch is sandboxed, and the sandbox will not let it read the motion
/// sensor's wake properties, run a user's shell command, or drive System
/// Events. The companion is not sandboxed and does all of that; Perch is the
/// interface. They share three things:
///
/// - **The settings file.** Perch writes it in its own container; the
///   companion, which lives inside Perch.app, works out where from Perch's
///   bundle identifier, and only ever reads it. Settings never travel
///   in a notification, because any process can post one, and a gesture map
///   can hold a shell command.
/// - **Commands**, Perch to companion, as distributed notifications whose
///   object is a short string. None of them carries anything that runs: the
///   worst a forged one can do is ask for a re-read, or run an action the
///   user already mapped.
/// - **Status**, companion to Perch, as distributed notifications whose
///   object is JSON. A sandboxed app may receive these but not attach a
///   `userInfo` to its own, which is why both directions use the object.
public enum TapLink {
    public static let commandNotification = Notification.Name("org.ahlab.Perch.tap.command")
    public static let statusNotification = Notification.Name("org.ahlab.Perch.tap.status")

    public static let companionBundleIdentifier = "org.ahlab.Perch.tap"
    /// Inside Perch.app.
    public static let companionPath = "Contents/Helpers/PerchTap.app"
    public static let pluginIdentifier = "org.ahlab.perch.tap"
    public static let configFilename = "tap.json"

    /// Overrides for running the companion by hand. Perch cannot pass them:
    /// LaunchServices drops the arguments of an app launched from a sandbox.
    public static let configArgument = "--config"
    public static let parentArgument = "--parent"

    /// Where Perch keeps Tap's settings, worked out from outside Perch's
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
        // PerchTap.app → Helpers → Contents → Perch.app
        companionURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// How often the companion says it is alive, and how long Perch waits
    /// without hearing it before starting another.
    public static let heartbeatInterval: TimeInterval = 1
    public static let heartbeatTimeout: TimeInterval = 6
    /// A view showing live sensor data renews this often; the companion stops
    /// streaming it when the renewals stop.
    public static let liveLease: TimeInterval = 3
}

public enum PermissionKind: String, Codable, CaseIterable, Sendable {
    case accessibility
    case inputMonitoring
    case automation
}

public enum TapCommand: Equatable, Sendable {
    /// Read the settings file again.
    case reload
    case quit
    /// Start or stop listening to the sensor.
    case start
    case stop
    /// Stream sensor data for the next `TapLink.liveLease` seconds.
    case live
    case request(PermissionKind)
    case openSystemSettings(PermissionKind)
    case previewHUD
    /// Run what this cell of the map does, as if knocked.
    case test(TapSide, Int)
    /// Debug builds only: the arrow keys knock.
    case simulateArrows(Bool)

    public var encoded: String {
        switch self {
        case .reload: "reload"
        case .quit: "quit"
        case .start: "start"
        case .stop: "stop"
        case .live: "live"
        case .request(let kind): "request:\(kind.rawValue)"
        case .openSystemSettings(let kind): "settings:\(kind.rawValue)"
        case .previewHUD: "preview"
        case .test(let side, let count): "test:\(side.rawValue):\(count)"
        case .simulateArrows(let on): "simulate:\(on ? 1 : 0)"
        }
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("reload", 1): self = .reload
        case ("quit", 1): self = .quit
        case ("start", 1): self = .start
        case ("stop", 1): self = .stop
        case ("live", 1): self = .live
        case ("preview", 1): self = .previewHUD
        case ("request", 2):
            guard let kind = PermissionKind(rawValue: parts[1]) else { return nil }
            self = .request(kind)
        case ("settings", 2):
            guard let kind = PermissionKind(rawValue: parts[1]) else { return nil }
            self = .openSystemSettings(kind)
        case ("test", 3):
            guard let side = TapSide(rawValue: parts[1]), let count = Int(parts[2]), (1...3).contains(count) else {
                return nil
            }
            self = .test(side, count)
        case ("simulate", 2):
            guard parts[1] == "0" || parts[1] == "1" else { return nil }
            self = .simulateArrows(parts[1] == "1")
        default:
            return nil
        }
    }
}

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    case notDetermined
    case unknown

    public var displayName: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .notDetermined: "Not Determined"
        case .unknown: "Unknown"
        }
    }
}

public struct TapPermissions: Codable, Equatable, Sendable {
    /// Required: keystrokes, media keys, lock screen.
    public var accessibility: PermissionState = .unknown
    /// macOS lists keystroke posting separately; either grant will do.
    public var postEvent: PermissionState = .unknown
    /// Optional: a second way to notice typing.
    public var inputMonitoring: PermissionState = .unknown
    /// System Events, which is how most shortcuts are typed.
    public var appleEvents: PermissionState = .unknown

    public init() {}

    public var canPostEvents: Bool { accessibility == .granted || postEvent == .granted }

    public func state(of kind: PermissionKind) -> PermissionState {
        switch kind {
        case .accessibility: canPostEvents ? .granted : accessibility
        case .inputMonitoring: inputMonitoring
        case .automation: appleEvents
        }
    }
}

public enum SensorSource: String, Codable, Sendable {
    case spu
    case keyboardSim
    case unavailable

    public var displayName: String {
        switch self {
        case .spu: "SPU IMU (accel + gyro)"
        case .keyboardSim: "Keyboard Simulation"
        case .unavailable: "Unavailable"
        }
    }
}

/// The sensor as it is right now, for the waveform and the Sensor pane.
/// Only sent while a view showing it has asked.
public struct LiveFrame: Codable, Equatable, Sendable {
    public var magnitude: [Float]
    public var x: [Float]
    public var y: [Float]
    public var z: [Float]
    public var sampleX: Double
    public var sampleY: Double
    public var sampleZ: Double
    public var sampleMagnitude: Double
    public var noiseFloor: Double
    public var pendingTapCount: Int
    public var lastRejectReason: String

    public init(
        magnitude: [Float] = [], x: [Float] = [], y: [Float] = [], z: [Float] = [],
        sampleX: Double = 0, sampleY: Double = 0, sampleZ: Double = 0, sampleMagnitude: Double = 0,
        noiseFloor: Double = 0, pendingTapCount: Int = 0, lastRejectReason: String = ""
    ) {
        self.magnitude = magnitude
        self.x = x
        self.y = y
        self.z = z
        self.sampleX = sampleX
        self.sampleY = sampleY
        self.sampleZ = sampleZ
        self.sampleMagnitude = sampleMagnitude
        self.noiseFloor = noiseFloor
        self.pendingTapCount = pendingTapCount
        self.lastRejectReason = lastRejectReason
    }

    /// The history in `count` buckets, newest last, so it fits a
    /// notification without losing its shape. Each bucket keeps its loudest
    /// value, so a 10 ms knock survives.
    public static func thin(_ values: [Double], to count: Int) -> [Float] {
        guard values.count > count, count > 0 else { return values.map(Float.init) }
        let step = Double(values.count) / Double(count)
        return (0..<count).map { i in
            let start = Int(Double(i) * step)
            let end = min(values.count, max(start + 1, Int(Double(i + 1) * step)))
            return Float(values[start..<end].max(by: { abs($0) < abs($1) }) ?? 0)
        }
    }
}

public struct TapStatus: Codable, Equatable, Sendable {
    public var source: SensorSource = .unavailable
    public var isStreaming = false
    public var gyroAvailable = false
    public var sampleRateHz: Double = 0
    public var sampleCount = 0
    public var lastError: String?
    public var configError: String?
    public var permissions = TapPermissions()
    /// Goes up by one for every knock, so Perch can tell a new one from a repeat.
    public var gestureSequence = 0
    public var lastGesture: DetectedGesture?
    /// What the last knock ran, if anything.
    public var lastExecuted: ActionType?
    public var stats = GestureStats()
    public var arrowSimulation = false
    public var live: LiveFrame?

    public init() {}

    public var isSensorAvailable: Bool { source == .spu || arrowSimulation }

    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public init?(encoded: String) {
        guard let value = try? JSONDecoder().decode(TapStatus.self, from: Data(encoded.utf8)) else { return nil }
        self = value
    }
}
