import Observation
import PerchKit
import SwiftUI

/// Whether the internet is working, and how well, a glance away: latency,
/// jitter and dropped checks, with the likely culprit named when it isn't.
///
/// Declares `.network` because it probes three public endpoints every 30
/// seconds while enabled, and downloads a test file when asked for a speed
/// test.
@MainActor
@Observable
public final class Internet: PerchPlugin {
    public static let identifier = "org.ahlab.perch.internet"
    public static let displayName = "Internet"
    public static let icon = "wifi"
    public static let capabilities: Set<PluginCapability> = [.network]

    /// Seconds between checks. A probe round is three tiny requests, so this
    /// can be frequent enough that the verdict tracks what is happening now.
    public static let interval: TimeInterval = 30

    public let store: InternetStore

    @ObservationIgnored private let pathWatcher: PathWatching
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    public required convenience init(context: PluginContext) {
        self.init(
            context: context,
            source: URLSessionProbeSource(),
            speedTester: CloudflareSpeedTester(),
            pathWatcher: NetworkPathWatcher()
        )
    }

    /// The testable initializer.
    public init(
        context: PluginContext,
        source: ProbeSource,
        speedTester: SpeedTester,
        pathWatcher: PathWatching
    ) {
        store = InternetStore(storage: context.storage, source: source, speedTester: speedTester)
        self.pathWatcher = pathWatcher
    }

    public var panel: AnyView {
        AnyView(InternetPanelView(store: store))
    }

    /// The icon carries the verdict so it can be read without reading; the
    /// text is the latency, which is the number that moves first when a line
    /// starts to struggle.
    public var menuBarLabel: MenuBarLabel? {
        let report = store.report
        let text: String? = switch report.verdict {
        case .good, .fair, .poor: report.latency.map(Format.milliseconds)
        case .checking, .offline, .noNetwork, .captivePortal, .dnsBroken: nil
        }
        return MenuBarLabel(systemImage: report.verdict.symbol, text: text)
    }

    public var footerActions: [PluginAction] {
        [
            PluginAction(id: "check", title: "Check now") { [store] in
                Task { await store.check() }
            }
        ]
    }

    public func flush() { store.saveNow() }

    public var isCheckLoopRunning: Bool { checkTask != nil }

    /// Probing the internet every 30 seconds is exactly the kind of thing a
    /// user expects to stop when they switch the plugin off.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            pathWatcher.start { [weak self] status in
                guard let store = self?.store else { return }
                Task { await store.pathChanged(status) }
            }
            startChecking()
        } else {
            pathWatcher.stop()
            checkTask?.cancel()
            checkTask = nil
        }
    }

    private func startChecking() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let store = self?.store else { return }
                await store.checkIfStale(maxAge: Self.interval - 1)
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }
}

extension HealthReport.Verdict {
    var symbol: String {
        switch self {
        case .checking, .good: "wifi"
        case .fair, .poor: "wifi.exclamationmark"
        case .offline, .noNetwork: "wifi.slash"
        case .captivePortal: "lock.shield"
        case .dnsBroken: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .good: .green
        case .fair: .yellow
        case .poor, .captivePortal, .dnsBroken: .orange
        case .offline, .noNetwork: .red
        }
    }
}
