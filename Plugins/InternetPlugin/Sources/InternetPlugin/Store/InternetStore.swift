import AppKit
import Foundation
import Observation
import PerchKit

/// Everything the plugin keeps on disk: recent checks, so the panel opens on
/// a trend rather than a blank, and the last speed test.
public struct InternetDocument: Codable, Equatable, Sendable {
    public var checks: [Check]
    public var speed: SpeedResult?

    public init(checks: [Check] = [], speed: SpeedResult? = nil) {
        self.checks = checks
        self.speed = speed
    }
}

/// The plugin's state, plus the checks and the speed test.
///
/// Writes are debounced, but `flush()` on the plugin and `willTerminate` both
/// force a synchronous save.
@MainActor
@Observable
public final class InternetStore {
    /// An hour at the 30-second interval: enough to see when a problem
    /// started, small enough that the document stays a few tens of kilobytes.
    public static let checkCapacity = 120

    public let targets: [ProbeTarget]
    public private(set) var checks: [Check] = []
    public private(set) var path: PathStatus?
    public private(set) var speed: SpeedResult?
    public private(set) var speedFailure: String?
    public private(set) var isChecking = false
    public private(set) var isTestingSpeed = false
    public private(set) var loadFailureNotice: String?
    public private(set) var saveFailureNotice: String?

    private let storage: PluginStorage
    private let source: ProbeSource
    private let speedTester: SpeedTester
    private let clock: () -> Date
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(
        storage: PluginStorage,
        source: ProbeSource,
        speedTester: SpeedTester,
        targets: [ProbeTarget] = ProbeTarget.defaults,
        clock: @escaping () -> Date = { .now },
        filename: String = "internet.json"
    ) {
        self.storage = storage
        self.source = source
        self.speedTester = speedTester
        self.targets = targets
        self.clock = clock
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Derived

    public var report: HealthReport {
        HealthReport.evaluate(checks: checks, path: path, targets: targets, now: clock())
    }

    public var lastChecked: Date? { checks.last?.at }

    public var latestOutcomes: [String: ProbeOutcome] { checks.last?.outcomes ?? [:] }

    // MARK: - Path

    /// A change of network — joining Wi-Fi, pulling a cable — is exactly when
    /// someone wants a fresh answer, so it triggers a check rather than
    /// waiting for the next tick.
    public func pathChanged(_ status: PathStatus) async {
        let previous = path
        path = status
        guard previous != nil, previous != status, status.isSatisfied else { return }
        await check()
    }

    // MARK: - Checking

    public func needsCheck(maxAge: TimeInterval) -> Bool {
        guard let lastChecked else { return true }
        return clock().timeIntervalSince(lastChecked) > maxAge
    }

    public func checkIfStale(maxAge: TimeInterval) async {
        guard needsCheck(maxAge: maxAge) else { return }
        await check()
    }

    /// Probes every target at once.
    ///
    /// Reentrancy is refused rather than queued: the loop, the panel opening
    /// and a network change can all land here together, and overlapping
    /// rounds would measure each other.
    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let source = source
        let outcomes = await withTaskGroup(of: (String, ProbeOutcome).self) { group in
            for target in targets {
                group.addTask { (target.id, await source.probe(target)) }
            }
            var outcomes: [String: ProbeOutcome] = [:]
            for await (id, outcome) in group { outcomes[id] = outcome }
            return outcomes
        }
        guard !Task.isCancelled else { return }
        checks.append(Check(at: clock(), outcomes: outcomes))
        if checks.count > Self.checkCapacity {
            checks.removeFirst(checks.count - Self.checkCapacity)
        }
        scheduleSave()
    }

    /// Only ever on request: a speed test moves tens of megabytes, which is
    /// not something to do behind someone's back.
    public func testSpeed() async {
        guard !isTestingSpeed else { return }
        isTestingSpeed = true
        defer { isTestingSpeed = false }
        do {
            let mbps = try await speedTester.measureDownload()
            speed = SpeedResult(megabitsPerSecond: mbps, at: clock())
            speedFailure = nil
            scheduleSave()
        } catch {
            speedFailure = "The speed test didn't finish."
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(InternetDocument.self, named: filename) else { return }
            checks = document.checks
            speed = document.speed
        } catch {
            loadFailureNotice = "Couldn't read the check history. A copy was kept as \(filename).bak."
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try storage.save(InternetDocument(checks: checks, speed: speed), named: filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save the check history."
        }
    }
}
