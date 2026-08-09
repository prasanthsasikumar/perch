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
    /// Consecutive polling rounds that scraped nothing at all before we stop
    /// believing the scraper works. Three is roughly 45 minutes at the default
    /// interval — late enough to be sure, early enough to be useful.
    public static let emptyRunThreshold = 3

    public private(set) var state: PollerState = .idle
    public private(set) var lastError: String?

    /// False once several consecutive rounds have scraped nothing whatsoever.
    ///
    /// A quiet search is normal; every watch returning zero listings, round
    /// after round, usually means the selectors broke or the session died in a
    /// way login detection missed. The panel says so rather than showing
    /// nothing and letting the user assume it is working.
    public var isScrapingHealthy: Bool { consecutiveEmptyRuns < Self.emptyRunThreshold }

    /// Deliberately *not* `@ObservationIgnored`: the panel renders
    /// `isScrapingHealthy`, so the counter behind it has to be observed or the
    /// warning row would never appear until some other change redrew the view.
    private var consecutiveEmptyRuns = 0
    @ObservationIgnored private var isTicking = false

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
        // Sign-in, the background loop, and any future "poll now" can all
        // reach here. `tick()` was written assuming it never runs concurrently
        // with itself; two overlapping runs would double-poll and interleave
        // store writes.
        guard !isTicking else { return [] }
        isTicking = true
        defer { isTicking = false }

        let now = clock()
        let due = store.watches.filter { !$0.paused && $0.nextCheckAt <= now }
        // No `if state == .polling { state = .idle }` here: at the top of
        // `tick()`, before the loop below has run at all, `state` can only
        // be whatever the PREVIOUS `tick()` call left it at — and every
        // `tick()` exit leaves it at a terminal value (`.idle`, `.signedOut`,
        // or `.backoff`) before returning, with `run()`'s loop never
        // overlapping two `tick()` calls. So `state` can never already be
        // `.polling` right here. (It very much CAN be `.polling` further
        // down, mid-loop — that path resets it explicitly below.)
        guard !due.isEmpty else { return [] }

        state = .polling
        var results: [(UUID, Int)] = []
        // Health is about scraping, not about finding: a round counts as
        // evidence only if it actually reached the source, and counts as empty
        // only if every watch it reached came back with nothing at all.
        var scrapedAnything = false
        var polledAnything = false

        for (position, watch) in due.enumerated() {
            // `stop()` cancels the loop, but without this an in-flight
            // `tick()` still runs every remaining due watch — with a real
            // source and several watches, that leaves Perch loading pages
            // for minutes after quit. `state` was just set to `.polling`
            // above (or left there by an earlier iteration), so this exit
            // must reset it to `.idle` itself — nothing further down ever
            // runs to do that for it.
            guard !Task.isCancelled else {
                state = .idle
                return results
            }
            do {
                let scraped = try await source.search(
                    query: watch.query,
                    maxPrice: watch.maxPrice,
                    location: watch.location,
                    radiusKm: watch.radiusKm
                )
                polledAnything = true
                if !scraped.isEmpty { scrapedAnything = true }
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
        // Only a round that actually polled something is evidence either way.
        // The `signedOut` path returns above without reaching here on purpose:
        // that state has its own message, and counting it here would show the
        // user two different explanations for one problem.
        if polledAnything {
            consecutiveEmptyRuns = scrapedAnything ? 0 : consecutiveEmptyRuns + 1
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

    /// Whether the background loop is live. The host's enable/disable hook is
    /// the only thing that should change this.
    public var isRunning: Bool { loop != nil }

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
