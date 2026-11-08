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

/// The plugin's state for one source, and the only thing the views talk to.
///
/// The plugin keeps one of these per `AnalyticsSource`, each with its own
/// cache file and Keychain item, which is what lets the user flip between
/// sources without losing either side's setup.
@MainActor
@Observable
public final class AnalyticsStore {
    /// How a live API is built from a credential. Injected so tests can swap
    /// in a stub without a network or a keychain.
    public typealias APIFactory = @Sendable (ServiceAccount) -> any GoogleAnalyticsAPI
    public typealias PostHogAPIFactory = @Sendable (PostHogCredential) -> any GoogleAnalyticsAPI

    static let cacheFilename = "analytics.json"
    static let postHogCacheFilename = "posthog.json"

    /// How each source turns its stored credential into an API.
    private enum Factory {
        case google(APIFactory)
        case postHog(PostHogAPIFactory)
    }

    public let source: AnalyticsSource

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

    /// The stored PostHog connection, so Settings can show its region,
    /// project and a masked key. Always `nil` for the GA store.
    public var postHogCredential: PostHogCredential? {
        loadCredentialIfNeeded()
        return loadedPostHogCredential
    }

    private var loadedPostHogCredential: PostHogCredential?

    private let storage: PluginStorage
    private let cacheFilename: String
    private let credentials: any CredentialStore
    private let factory: Factory
    private let now: () -> Date

    private var api: (any GoogleAnalyticsAPI)?
    /// Whether `loadCredential()` has run yet. Guards it to at most once, so
    /// every access after the first is a plain read rather than another trip
    /// to the Keychain.
    private var didLoadCredential = false

    public convenience init(
        storage: PluginStorage,
        credentials: any CredentialStore,
        apiFactory: @escaping APIFactory = { LiveGoogleAnalyticsAPI(account: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            source: .googleAnalytics,
            storage: storage,
            cacheFilename: Self.cacheFilename,
            credentials: credentials,
            factory: .google(apiFactory),
            now: now
        )
    }

    /// The PostHog store. Its own cache file, so the two sources' sites and
    /// numbers never mix, and its own Keychain item, passed in as
    /// `credentials`.
    public convenience init(
        postHogStorage storage: PluginStorage,
        credentials: any CredentialStore,
        apiFactory: @escaping PostHogAPIFactory = { LivePostHogAPI(credential: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            source: .postHog,
            storage: storage,
            cacheFilename: Self.postHogCacheFilename,
            credentials: credentials,
            factory: .postHog(apiFactory),
            now: now
        )
    }

    private init(
        source: AnalyticsSource,
        storage: PluginStorage,
        cacheFilename: String,
        credentials: any CredentialStore,
        factory: Factory,
        now: @escaping () -> Date
    ) {
        self.source = source
        self.storage = storage
        self.cacheFilename = cacheFilename
        self.credentials = credentials
        self.factory = factory
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

    /// `nil` rather than empty for PostHog, which has no such address, so
    /// the views' "add this account as a viewer" wording never appears there.
    public var clientEmail: String? {
        loadCredentialIfNeeded()
        guard let email = api?.clientEmail, !email.isEmpty else { return nil }
        return email
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
        guard case .google(let apiFactory) = factory else { throw AnalyticsError.notConfigured }
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

    /// Validates and stores a PostHog connection, and starts using it.
    ///
    /// Region, project and key go into the Keychain together; none of them
    /// is written to the plugin's cache.
    public func connectPostHog(
        region: PostHogCredential.Region, projectID: String, apiKey: String
    ) throws {
        guard case .postHog(let apiFactory) = factory else { throw AnalyticsError.notConfigured }
        let credential = try PostHogCredential.validated(region: region, projectID: projectID, apiKey: apiKey)
        let changedProject = loadedPostHogCredential.map {
            $0.projectID != credential.projectID || $0.region != credential.region
        } ?? false
        try credentials.save(try JSONEncoder().encode(credential))
        api = apiFactory(credential)
        loadedPostHogCredential = credential
        credentialFailure = nil
        didLoadCredential = true
        // A different project has different sites; numbers cached from the
        // old one would sit under the new one's name otherwise.
        if changedProject {
            stats.removeAll()
            failures.removeAll()
            lastRefreshed = nil
            persist()
        }
    }

    public func removeCredential() throws {
        try credentials.remove()
        api = nil
        loadedPostHogCredential = nil
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
        guard let data = try? credentials.load() else {
            credentialFailure = .notConfigured
            return
        }
        switch factory {
        case .google(let apiFactory):
            guard let account = try? JSONDecoder().decode(ServiceAccount.self, from: data) else {
                credentialFailure = .notConfigured
                return
            }
            api = apiFactory(account)
        case .postHog(let apiFactory):
            guard let credential = try? JSONDecoder().decode(PostHogCredential.self, from: data) else {
                credentialFailure = .notConfigured
                return
            }
            loadedPostHogCredential = credential
            api = apiFactory(credential)
        }
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

    /// Not cached and not part of `refresh()`: the detail window asks when it
    /// opens, so the background loop never pays for seven extra reports.
    public func breakdown(for propertyID: String) async throws -> PropertyBreakdown {
        loadCredentialIfNeeded()
        guard let api else { throw AnalyticsError.notConfigured }
        return try await api.breakdown(for: propertyID, today: now())
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

        let results = await api.stats(for: ids, today: today)

        // Toggling the plugin off mid-fetch cancels this task. Without this
        // check, the in-flight `stats(for:today:)` calls throw a
        // cancellation error, the generic `catch` in `GoogleAnalyticsAPI.stats(for:today:)`
        // maps it to
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
            named: cacheFilename
        )
    }

    private func persist() { saveNow() }

    private func loadCache() {
        // An unreadable cache is not worth surfacing: `PluginStorage` has
        // already kept a `.bak`, and everything in here is refetchable.
        guard let cache = try? storage.load(AnalyticsCache.self, named: cacheFilename) else { return }
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
