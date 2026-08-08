import Foundation
import Observation
import PerchKit

/// Everything on disk between launches: the watched properties, the last
/// numbers fetched for each, and when that was.
///
/// Caching the stats is what lets the panel open on real numbers instead of a
/// spinner. They are a few hundred bytes and they are already public web
/// analytics, so there is nothing here worth protecting beyond the sandbox.
struct AnalyticsCache: Codable {
    var properties: [AnalyticsProperty] = []
    var stats: [String: PropertyStats] = [:]
    var primaryPropertyID: String?
    var lastRefreshed: Date?
}

/// The plugin's state, and the only thing the views talk to.
@MainActor
@Observable
public final class AnalyticsStore {
    /// How a live API is built from a credential. Injected so tests can swap
    /// in a stub without a network or a keychain.
    public typealias APIFactory = @Sendable (ServiceAccount) -> any GoogleAnalyticsAPI

    static let cacheFilename = "analytics.json"

    public private(set) var properties: [AnalyticsProperty] = []
    public private(set) var stats: [String: PropertyStats] = [:]
    /// Keyed by property id. A property that fails leaves the others alone.
    public private(set) var failures: [String: AnalyticsError] = [:]
    /// Set when the *credential* is the problem, which is a banner rather than
    /// a per-property message because re-importing the key fixes all of them.
    public private(set) var credentialFailure: AnalyticsError?
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false

    public var primaryPropertyID: String? {
        didSet { persist() }
    }

    private let storage: PluginStorage
    private let credentials: any CredentialStore
    private let apiFactory: APIFactory
    private let now: () -> Date

    private var api: (any GoogleAnalyticsAPI)?
    /// Whether `loadCredential()` has run yet. Guards it to at most once, so
    /// every access after the first is a plain read rather than another trip
    /// to the Keychain.
    private var didLoadCredential = false

    public init(
        storage: PluginStorage,
        credentials: any CredentialStore,
        apiFactory: @escaping APIFactory = { LiveGoogleAnalyticsAPI(account: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.credentials = credentials
        self.apiFactory = apiFactory
        self.now = now

        loadCache()
        // Deliberately not `loadCredential()`: constructing a store must not
        // touch the Keychain. This runs whenever the `Analytics` plugin is
        // constructed — including when the user has it switched off, and
        // including when Perch is launched as an XCTest host — and Perch is
        // ad-hoc signed, so every rebuild changes the code signature the
        // Keychain ACL trusts, turning every launch into a "Perch wants to
        // use your confidential information" prompt. The credential is read
        // lazily instead, the first time something genuinely needs it.
    }

    // MARK: - Configuration

    public var isConfigured: Bool {
        loadCredentialIfNeeded()
        return api != nil
    }

    public var clientEmail: String? {
        loadCredentialIfNeeded()
        return api?.clientEmail
    }

    /// Reads a service-account JSON, stores it, and starts using it.
    ///
    /// The file is read once and never referenced again: no copy in the
    /// container, no security-scoped bookmark. What the user picked in the
    /// open panel is the grant, and it ends when this returns.
    public func importCredential(from url: URL) throws {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        try importCredential(keyFile: try Data(contentsOf: url))
    }

    public func importCredential(keyFile data: Data) throws {
        let account = try ServiceAccount(keyFile: data)
        try credentials.save(try JSONEncoder().encode(account))
        api = apiFactory(account)
        credentialFailure = nil
        // The credential just written *is* the current truth: mark it loaded
        // so a later `loadCredentialIfNeeded()` — triggered by, say, the next
        // `isConfigured` read — does not go back to the Keychain and clobber
        // what the user just imported with whatever it reads back.
        didLoadCredential = true
    }

    public func removeCredential() throws {
        try credentials.remove()
        api = nil
        // The numbers came from a credential the user just revoked, so they
        // should not keep sitting in the panel as though they were live.
        stats.removeAll()
        failures.removeAll()
        lastRefreshed = nil
        credentialFailure = .notConfigured
        persist()
        // As above: this is now the current truth (no credential), so later
        // reads must not re-hit the Keychain looking for one.
        didLoadCredential = true
    }

    /// Reads the Keychain at most once — the first time something genuinely
    /// needs the credential — never merely because a store was constructed.
    private func loadCredentialIfNeeded() {
        guard !didLoadCredential else { return }
        didLoadCredential = true
        loadCredential()
    }

    private func loadCredential() {
        guard let data = try? credentials.load(),
              let account = try? JSONDecoder().decode(ServiceAccount.self, from: data) else {
            credentialFailure = .notConfigured
            return
        }
        api = apiFactory(account)
    }

    // MARK: - Properties

    public func setProperties(_ new: [AnalyticsProperty]) {
        properties = new
        let known = Set(new.map(\.id))
        stats = stats.filter { known.contains($0.key) }
        failures = failures.filter { known.contains($0.key) }
        if primaryPropertyID == nil || !known.contains(primaryPropertyID!) {
            primaryPropertyID = new.first?.id
        }
        persist()
    }

    public func addProperty(_ property: AnalyticsProperty) {
        guard !properties.contains(where: { $0.id == property.id }) else { return }
        setProperties(properties + [property])
    }

    public func removeProperty(id: String) {
        setProperties(properties.filter { $0.id != id })
    }

    /// GA's own names are whatever was typed into the console years ago —
    /// "homepage" rather than the domain. Renaming is local only; nothing is
    /// written back to Google.
    public func renameProperty(id: String, to name: String) {
        guard let index = properties.firstIndex(where: { $0.id == id }) else { return }
        properties[index].displayName = name
        persist()
    }

    public func discoverProperties() async throws -> [AnalyticsProperty] {
        loadCredentialIfNeeded()
        guard let api else { throw AnalyticsError.notConfigured }
        return try await api.discoverProperties()
    }

    // MARK: - Refresh

    /// True when the cache is older than `maxAge`, or there is no cache.
    public func needsRefresh(maxAge: TimeInterval) -> Bool {
        guard let lastRefreshed else { return true }
        return now().timeIntervalSince(lastRefreshed) > maxAge
    }

    public func refreshIfStale(maxAge: TimeInterval) async {
        guard needsRefresh(maxAge: maxAge) else { return }
        await refresh()
    }

    public func refresh() async {
        loadCredentialIfNeeded()
        guard let api else {
            credentialFailure = .notConfigured
            return
        }
        guard !properties.isEmpty, !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let today = now()
        let ids = properties.map(\.id)

        // Concurrently, because one slow property should not hold up the rest
        // and the panel renders each card independently anyway.
        let results = await withTaskGroup(
            of: (String, Result<PropertyStats, AnalyticsError>).self
        ) { group -> [(String, Result<PropertyStats, AnalyticsError>)] in
            for id in ids {
                group.addTask {
                    do {
                        return (id, .success(try await api.stats(for: id, today: today)))
                    } catch let error as AnalyticsError {
                        return (id, .failure(error))
                    } catch {
                        return (id, .failure(.malformedResponse))
                    }
                }
            }
            var collected: [(String, Result<PropertyStats, AnalyticsError>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        // Toggling the plugin off mid-fetch cancels this task. Without this
        // check, the in-flight `stats(for:today:)` calls throw a
        // cancellation error, the generic `catch` above maps it to
        // `.malformedResponse`, and `apply` records a spurious "Couldn't
        // refresh" failure that can persist on re-enable even though nothing
        // was actually wrong.
        // Toggling the plugin off mid-fetch cancels this task. Without this
        // check, the in-flight `stats(for:today:)` calls throw a
        // cancellation error, the generic `catch` above maps it to
        // `.malformedResponse`, and `apply` records a spurious "Couldn't
        // refresh" failure that can persist on re-enable even though nothing
        // was actually wrong.
        guard !Task.isCancelled else { return }
        apply(results)
    }

    private func apply(_ results: [(String, Result<PropertyStats, AnalyticsError>)]) {
        var credentialProblem: AnalyticsError?
        var anySucceeded = false

        for (id, result) in results {
            switch result {
            case .success(let value):
                stats[id] = value
                failures[id] = nil
                anySucceeded = true
            case .failure(let error):
                // Deliberately keeps `stats[id]`: showing yesterday's numbers
                // and saying so beats blanking the card because the wifi
                // dropped.
                failures[id] = error
                if error.isCredentialProblem { credentialProblem = error }
            }
        }

        credentialFailure = credentialProblem
        // Only moves when something actually arrived, so "updated 3 hours ago"
        // stays honest about the age of what is on screen.
        if anySucceeded { lastRefreshed = now() }
        persist()
    }

    // MARK: - Persistence

    /// Synchronous write for `PerchPlugin.flush()`.
    public func saveNow() {
        try? storage.save(
            AnalyticsCache(
                properties: properties,
                stats: stats,
                primaryPropertyID: primaryPropertyID,
                lastRefreshed: lastRefreshed
            ),
            named: Self.cacheFilename
        )
    }

    private func persist() { saveNow() }

    private func loadCache() {
        // An unreadable cache is not worth surfacing: `PluginStorage` has
        // already kept a `.bak`, and everything in here is refetchable.
        guard let cache = try? storage.load(AnalyticsCache.self, named: Self.cacheFilename) else { return }
        properties = cache.properties
        stats = cache.stats
        primaryPropertyID = cache.primaryPropertyID ?? cache.properties.first?.id
        lastRefreshed = cache.lastRefreshed
    }

    // MARK: - Derived

    public var primaryProperty: AnalyticsProperty? {
        properties.first { $0.id == primaryPropertyID } ?? properties.first
    }

    public var primaryStats: PropertyStats? {
        primaryProperty.flatMap { stats[$0.id] }
    }

    /// The number the menu bar shows.
    public var menuBarUsers: Double? {
        primaryStats?.latestActiveUsers
    }
}
