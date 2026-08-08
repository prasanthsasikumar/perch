import Foundation
import Observation

public enum PollerState: Equatable {
    case idle
    case polling
    case signedOut
    case backoff
}

/// The loop.
///
/// Strictly serial, on purpose: there is one webview behind `ListingSource`,
/// and polling Facebook in parallel from one address is how a session gets
/// killed. Jitter keeps checks off a fixed cadence.
@MainActor
@Observable
public final class WatchPoller {
    public static let minIntervalSeconds: TimeInterval = 600
    public static let maxBackoffSeconds: TimeInterval = 7200
    public static let signInRetrySeconds: TimeInterval = 60

    /// How often the loop wakes to see whether anything is due. Not the poll
    /// interval — that is per watch, and much longer.
    static let tickIntervalSeconds: TimeInterval = 30

    public private(set) var state: PollerState = .idle
    public private(set) var lastError: String?

    private let store: MarketStore
    private let source: ListingSource
    private let clock: () -> Date
    private let jitter: (Double, Double) -> Double
    private let onFinds: ((UUID, Int) -> Void)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        store: MarketStore,
        source: ListingSource,
        clock: @escaping () -> Date = { .now },
        jitter: @escaping (Double, Double) -> Double = { Double.random(in: $0...$1) },
        onFinds: ((UUID, Int) -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.clock = clock
        self.jitter = jitter
        self.onFinds = onFinds
    }

    /// Polls every watch that is due. Returns one pair per watch that found
    /// something new.
    @discardableResult
    public func tick() async -> [(UUID, Int)] {
        let now = clock()
        let due = store.watches.filter { !$0.paused && $0.nextCheckAt <= now }
        guard !due.isEmpty else {
            if state == .polling { state = .idle }
            return []
        }

        state = .polling
        var results: [(UUID, Int)] = []

        for (position, watch) in due.enumerated() {
            do {
                let scraped = try await source.search(
                    query: watch.query,
                    maxPrice: watch.maxPrice,
                    location: watch.location,
                    radiusKm: watch.radiusKm
                )
                let fresh = store.record(scraped, for: watch.id)
                reschedule(watch, after: interval(), failures: 0)
                if !fresh.isEmpty {
                    results.append((watch.id, fresh.count))
                    onFinds?(watch.id, fresh.count)
                }
            } catch SearchError.signedOut {
                // A human problem, not a flaky scrape: no failure count, no
                // backoff, and no point trying the rest — they hit the same
                // wall. Push every watch we have not yet attempted past the
                // retry window, or the next tick just picks a different one.
                state = .signedOut
                lastError = nil
                for pending in due[position...] {
                    reschedule(
                        pending,
                        after: Self.signInRetrySeconds,
                        failures: pending.consecutiveFailures,
                        checked: false
                    )
                }
                return results
            } catch {
                state = .backoff
                lastError = Self.describe(error)
                let failures = watch.consecutiveFailures + 1
                reschedule(watch, after: backoff(failures: failures), failures: failures)
                continue
            }
        }

        if state == .polling {
            state = .idle
            lastError = nil
        }
        return results
    }

    /// Runs `tick()` forever, waking every 30 seconds to see what is due.
    /// Holds only a weak reference, so it returns once the plugin is gone.
    public func run() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Self.tickIntervalSeconds))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - Scheduling

    private func reschedule(
        _ watch: Watch, after seconds: TimeInterval, failures: Int, checked: Bool = true
    ) {
        var updated = watch
        updated.consecutiveFailures = failures
        if checked { updated.lastCheckedAt = clock() }
        updated.nextCheckAt = clock().addingTimeInterval(seconds)
        store.update(updated)
    }

    private func interval() -> TimeInterval {
        let configured = TimeInterval(store.settings.pollIntervalMinutes * 60)
        let base = max(configured, Self.minIntervalSeconds)
        // Clamped after jitter, not before: a 0.8 draw on a floor-length base
        // would otherwise schedule below the floor.
        return max(base * jitter(0.8, 1.2), Self.minIntervalSeconds)
    }

    private func backoff(failures: Int) -> TimeInterval {
        let base = min(Self.minIntervalSeconds * pow(2, Double(failures)), Self.maxBackoffSeconds)
        return min(base * jitter(0.8, 1.2), Self.maxBackoffSeconds)
    }

    private static func describe(_ error: Error) -> String {
        if case SearchError.failed(let message) = error { return message }
        return String(describing: error)
    }
}
