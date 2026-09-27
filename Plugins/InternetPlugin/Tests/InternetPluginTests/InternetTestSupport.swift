@testable import InternetPlugin
import Foundation
import PerchKit

/// Answers each target with whatever was queued for it, `.ok(20)` otherwise,
/// and counts how often it was asked.
final class FakeProbeSource: ProbeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _outcomes: [String: ProbeOutcome] = [:]
    private var _calls = 0

    var calls: Int { lock.withLock { _calls } }

    func set(_ id: String, _ outcome: ProbeOutcome) {
        lock.withLock { _outcomes[id] = outcome }
    }

    func setAll(_ outcome: ProbeOutcome) {
        lock.withLock {
            for target in ProbeTarget.defaults { _outcomes[target.id] = outcome }
        }
    }

    func probe(_ target: ProbeTarget) async -> ProbeOutcome {
        lock.withLock {
            _calls += 1
            return _outcomes[target.id] ?? .ok(milliseconds: 20)
        }
    }
}

final class FakeSpeedTester: SpeedTester, @unchecked Sendable {
    var result: Result<Double, Error> = .success(100)

    func measureDownload() async throws -> Double {
        try result.get()
    }
}

@MainActor
final class FakePathWatcher: PathWatching {
    private(set) var isRunning = false
    private(set) var onChange: (@MainActor (PathStatus) -> Void)?

    func start(onChange: @escaping @MainActor (PathStatus) -> Void) {
        isRunning = true
        self.onChange = onChange
    }

    func stop() {
        isRunning = false
        onChange = nil
    }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { _now } }

    func advance(_ interval: TimeInterval) {
        lock.withLock { _now += interval }
    }
}

func makeTemporaryStorage() -> PluginStorage {
    PluginStorage(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("InternetPluginTests-\(UUID().uuidString)", isDirectory: true))
}

/// A check where every default target gave `outcome`, unless overridden.
func makeCheck(
    at: Date,
    _ outcome: ProbeOutcome = .ok(milliseconds: 20),
    overrides: [String: ProbeOutcome] = [:]
) -> Check {
    var outcomes = Dictionary(uniqueKeysWithValues: ProbeTarget.defaults.map { ($0.id, outcome) })
    outcomes.merge(overrides) { $1 }
    return Check(at: at, outcomes: outcomes)
}

let wifi = PathStatus(isSatisfied: true, interface: .wifi)
