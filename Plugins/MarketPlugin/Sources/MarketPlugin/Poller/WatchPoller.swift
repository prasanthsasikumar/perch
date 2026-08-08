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

    public private(set) var state: PollerState = .idle
    public private(set) var lastError: String?

    private let store: MarketStore
    private let source: ListingSource
    private let clock: () -> Date
    private let jitter: (Double, Double) -> Double
    private let onFinds: ((UUID, Int) -> Void)?
    /// How often the loop wakes to see whether anything is due. Not the poll
    /// interval — that is per watch, and much longer. Injectable so a test
    /// can exercise `run()`/`stop()` without a real 30-second wait.
    private let tickIntervalSeconds: TimeInterval
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        store: MarketStore,
        source: ListingSource,
        clock: @escaping () -> Date = { .now },
        jitter: @escaping (Double, Double) -> Double = { Double.random(in: $0...$1) },
        tickIntervalSeconds: TimeInterval = 30,
        onFinds: ((UUID, Int) -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.clock = clock
        self.jitter = jitter
        self.tickIntervalSeconds = tickIntervalSeconds
        self.onFinds = onFinds
    }

    /// Polls every watch that is due. Returns one pair per watch that found
    /// something new.
    @discardableResult
    public func tick() async -> [(UUID, Int)] {
        let now = clock()
        let due = store.watches.filter { !$0.paused && $0.nextCheckAt <= now }
        // No `if state == .polling { state = .idle }` here: every exit below
        // already leaves `state` at a terminal value (`.idle`, `.signedOut`,
        // or `.backoff`) before `tick()` returns, and `run()`'s loop never
        // overlaps two `tick()` calls — so `state` can never already be
        // `.polling` when a fresh call starts.
        guard !due.isEmpty else { return [] }

        state = .polling
        var results: [(UUID, Int)] = []

        for (position, watch) in due.enumerated() {
            // `stop()` cancels the loop, but without this an in-flight
            // `tick()` still runs every remaining due watch — with a real
            // source and several watches, that leaves Perch loading pages
            // for minutes after quit.
            guard !Task.isCancelled else { return results }
            do {
                let scraped = try await source.search(
                    query: watch.query,
                    maxPrice: watch.maxPrice,
                    location: watch.location,
                    radiusKm: watch.radiusKm
                )
                // The MainActor served other work during that `await` — a
                // watch paused, edited, or deleted while its own search was
                // in flight must not have that change silently reverted by
                // writing back the snapshot taken before the loop started.
                // A deleted watch (not found here) records nothing rather
                // than resurrecting it as an orphan.
                guard let current = store.watches.first(where: { $0.id == watch.id }) else {
                    continue
                }
                let fresh = store.record(scraped, for: watch.id)
                reschedule(current, after: interval(), failures: 0)
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
                    guard let current = store.watches.first(where: { $0.id == pending.id })
                    else { continue }
                    reschedule(
                        current,
                        after: Self.signInRetrySeconds,
                        failures: current.consecutiveFailures,
                        checked: false
                    )
                }
                return results
            } catch {
                guard let current = store.watches.first(where: { $0.id == watch.id }) else {
                    continue
                }
                state = .backoff
                lastError = Self.describe(error)
                let failures = current.consecutiveFailures + 1
                reschedule(current, after: backoff(failures: failures), failures: failures)
                continue
            }
        }

        if state == .polling {
            state = .idle
            lastError = nil
        }
        return results
    }

    /// Runs `tick()` forever, waking every `tickIntervalSeconds` to see
    /// what is due.
    ///
    /// The loop binds `self` strongly only for the duration of `tick()` —
    /// the `if let self { … } else { break }` scope ends before the sleep,
    /// so nothing holds the poller alive across it. Once the plugin is
    /// gone, the next wake finds `self` `nil` and the loop exits instead of
    /// spinning forever.
    public func run() {
        loop?.cancel()
        let tickIntervalSeconds = tickIntervalSeconds
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self { await self.tick() } else { break }
                try? await Task.sleep(for: .seconds(tickIntervalSeconds))
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
        // Any other error type reaches the UI as-is otherwise — once Plan 2
        // adds a real source, a `WKError`'s debug description would land in
        // a user-facing caption.
        return "Something went wrong while checking for listings."
    }
}
