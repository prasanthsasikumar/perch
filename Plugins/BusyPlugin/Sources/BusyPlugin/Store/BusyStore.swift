import AppKit
import Foundation
import Observation
import PerchKit

/// The plugin's state, persisted as one JSON document, plus the refresh.
///
/// Writes are debounced, but `flush()` on the plugin and `willTerminate`
/// both force a synchronous save, so nothing is lost on quit.
@MainActor
@Observable
public final class BusyStore {
    public private(set) var places: [Place] = []
    public private(set) var results: [UUID: Busyness] = [:]
    /// The message under a place whose last fetch failed. Its previous
    /// result, if any, stays in `results` — stale numbers dimmed beat no
    /// numbers.
    public private(set) var failures: [UUID: String] = [:]
    public private(set) var settings: BusySettings = .defaults
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false
    public private(set) var loadFailureNotice: String?
    public private(set) var saveFailureNotice: String?

    private let storage: PluginStorage
    private let source: BusynessSource
    private let clock: () -> Date
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(
        storage: PluginStorage,
        source: BusynessSource,
        clock: @escaping () -> Date = { .now },
        filename: String = "busy.json"
    ) {
        self.storage = storage
        self.source = source
        self.clock = clock
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Places

    @discardableResult
    public func addPlace(query: String) -> Place? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let place = Place(query: trimmed, createdAt: clock())
        places.append(place)
        scheduleSave()
        return place
    }

    public func deletePlace(id: UUID) {
        places.removeAll { $0.id == id }
        results[id] = nil
        failures[id] = nil
        scheduleSave()
    }

    public func updateSettings(_ newValue: BusySettings) {
        settings = newValue
        scheduleSave()
    }

    // MARK: - Refresh

    /// Stale numbers, or a place that has never had numbers at all. The
    /// second clause matters after a failed first fetch: `lastRefreshed` is
    /// recorded either way, and without it a place could sit at "not checked
    /// yet" for a whole interval while the store believed it was fresh.
    public func needsRefresh(maxAge: TimeInterval) -> Bool {
        if places.contains(where: { results[$0.id] == nil }) { return true }
        guard let lastRefreshed else { return true }
        return clock().timeIntervalSince(lastRefreshed) > maxAge
    }

    public func refreshIfStale(maxAge: TimeInterval) async {
        guard needsRefresh(maxAge: maxAge) else { return }
        await refresh()
    }

    /// Fetches every place, one after another.
    ///
    /// Serial on purpose: there is one webview behind the source. Reentrancy
    /// is refused rather than queued — the panel's on-open refresh and the
    /// background loop can both land here, and two interleaved passes would
    /// double-load every page.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for place in places {
            guard !Task.isCancelled else { return }
            do {
                let reading = try await source.fetch(query: place.query)
                // The MainActor served other work during that `await` — a
                // place deleted while its own fetch was in flight must not
                // come back as an orphaned result.
                guard places.contains(where: { $0.id == place.id }) else { continue }
                results[place.id] = Busyness(reading: reading, fetchedAt: clock())
                failures[place.id] = nil
            } catch let error as BusyError {
                guard places.contains(where: { $0.id == place.id }) else { continue }
                failures[place.id] = error.message
            } catch {
                guard places.contains(where: { $0.id == place.id }) else { continue }
                // Any other error type would otherwise reach the panel as-is,
                // and a `WKError`'s debug description is not a caption.
                failures[place.id] = "Something went wrong while checking."
            }
        }
        lastRefreshed = clock()
        scheduleSave()
    }

    // MARK: - Derived

    /// What the menu bar shows: the first place's live figure, when there is one.
    public var menuBarPercent: Int? {
        guard let first = places.first else { return nil }
        return results[first.id]?.reading.livePercent
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(BusyDocument.self, named: filename) else { return }
            places = document.places
            results = document.results
            settings = document.settings
            lastRefreshed = document.lastRefreshed
        } catch {
            // PluginStorage kept a .bak beside the file, so nothing is lost —
            // but the user should know why their places vanished.
            loadFailureNotice = "Couldn't read your places. A copy was kept as busy.json.bak."
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
        let document = BusyDocument(
            places: places,
            results: results,
            settings: settings,
            lastRefreshed: lastRefreshed
        )
        do {
            try storage.save(document, named: filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save your places. Changes may be lost if Perch quits."
        }
    }
}
