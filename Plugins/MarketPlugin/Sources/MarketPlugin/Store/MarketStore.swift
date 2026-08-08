import AppKit
import Foundation
import Observation
import PerchKit

/// The plugin's state, persisted as one JSON document.
///
/// Writes are debounced — a poll can record a dozen listings in a burst, and
/// rewriting the file per listing would be wasteful — but `flush()` on the
/// plugin and `willTerminate` both force a synchronous save, so nothing is
/// lost on quit.
@MainActor
@Observable
public final class MarketStore {
    /// Enough history for any view we show, and it bounds the file without a
    /// retention setting nobody would tune.
    public static let listingsPerWatchCap = 200

    public private(set) var watches: [Watch] = []
    public private(set) var settings: MarketSettings = .defaults
    public private(set) var loadFailureNotice: String?

    private var listingsByWatch: [UUID: [Listing]] = [:]
    private let storage: PluginStorage
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(storage: PluginStorage, filename: String = "market.json") {
        self.storage = storage
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Watches

    /// Facebook scopes marketplace searches to a city. Without one a search
    /// returns nothing while raising nothing, so we refuse rather than create
    /// a watch that can never match.
    public var canAddWatch: Bool {
        !(settings.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    @discardableResult
    public func addWatch(query: String, maxPrice: Int?) -> Watch? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAddWatch, let location = settings.location else { return nil }

        let watch = Watch(
            query: trimmed,
            maxPrice: maxPrice,
            location: location,
            radiusKm: settings.radiusKm
        )
        watches.append(watch)
        scheduleSave()
        return watch
    }

    public func deleteWatch(id: UUID) {
        watches.removeAll { $0.id == id }
        listingsByWatch[id] = nil
        scheduleSave()
    }

    public func update(_ watch: Watch) {
        guard let index = watches.firstIndex(where: { $0.id == watch.id }) else { return }
        watches[index] = watch
        scheduleSave()
    }

    public func updateSettings(_ newValue: MarketSettings) {
        settings = newValue
        scheduleSave()
    }

    // MARK: - Listings

    /// Records whatever is new for this watch and returns just those.
    @discardableResult
    public func record(_ scraped: [ScrapedListing], for watchID: UUID) -> [Listing] {
        let existing = listingsByWatch[watchID] ?? []
        let seenIDs = Set(existing.map(\.id))
        let fresh = newListings(scraped, seenIDs: seenIDs).map {
            Listing(
                id: $0.id,
                watchID: watchID,
                title: $0.title,
                price: $0.price,
                location: $0.location,
                url: $0.url,
                imageURL: $0.imageURL
            )
        }
        guard !fresh.isEmpty else { return [] }

        // Newest first, capped. Dropping from the tail drops the oldest.
        listingsByWatch[watchID] = Array((fresh + existing).prefix(Self.listingsPerWatchCap))
        scheduleSave()
        return fresh
    }

    public func listings(for watchID: UUID) -> [Listing] {
        listingsByWatch[watchID] ?? []
    }

    public func newest(for watchID: UUID, limit: Int) -> [Listing] {
        Array(listings(for: watchID).prefix(limit))
    }

    public func unseenCount(for watchID: UUID) -> Int {
        // `count(where:)` is Swift 6.0; this package is 5.9.
        listings(for: watchID).filter { !$0.seen }.count
    }

    public var totalUnseen: Int {
        watches.reduce(0) { $0 + unseenCount(for: $1.id) }
    }

    public func markSeen(watchID: UUID) {
        guard var existing = listingsByWatch[watchID] else { return }
        for index in existing.indices { existing[index].seen = true }
        listingsByWatch[watchID] = existing
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(MarketDocument.self, named: filename) else {
                return
            }
            watches = document.watches
            settings = document.settings
            listingsByWatch = Dictionary(grouping: document.listings, by: \.watchID)
        } catch {
            // PluginStorage kept a .bak beside the file, so nothing is lost —
            // but the user should know why their watches vanished.
            loadFailureNotice = "Couldn't read your watches. A copy was kept as market.json.bak."
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
        let document = MarketDocument(
            watches: watches,
            listings: listingsByWatch.values.flatMap { $0 },
            settings: settings
        )
        try? storage.save(document, named: filename)
    }
}
