import AppKit
import Foundation
import Observation
import PerchKit

/// The plugin's state, persisted as one JSON document, plus the refresh.
///
/// Writes are debounced, but `flush()` on the plugin and `willTerminate` both
/// force a synchronous save, so nothing is lost on quit.
@MainActor
@Observable
public final class ServerStore {
    /// How many readings a card's sparkline keeps. At the default minute
    /// interval that is two hours, which is long enough to see a spike start
    /// and short enough that the document stays small.
    public static let trendCapacity = 120

    public private(set) var servers: [ServerTarget] = []
    public private(set) var snapshots: [UUID: HostSnapshot] = [:]
    /// The message under a server whose last fetch failed. Its previous
    /// snapshot, if any, stays in `snapshots` — stale numbers dimmed beat no
    /// numbers.
    public private(set) var failures: [UUID: String] = [:]
    public private(set) var trends: [UUID: [TrendPoint]] = [:]
    public private(set) var settings: ServerSettings = .defaults
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false
    public private(set) var loadFailureNotice: String?
    public private(set) var saveFailureNotice: String?
    /// Set when the Keychain refused to hold a password. Without this the
    /// server is added, the password is gone, and every refresh reports a
    /// wrong password instead of the truth.
    public private(set) var credentialFailureNotice: String?

    private let storage: PluginStorage
    private let source: SnapshotSource
    private let credentials: ServerCredentialStore
    private let clock: () -> Date
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(
        storage: PluginStorage,
        source: SnapshotSource,
        credentials: ServerCredentialStore,
        clock: @escaping () -> Date = { .now },
        filename: String = "servers.json"
    ) {
        self.storage = storage
        self.source = source
        self.credentials = credentials
        self.clock = clock
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Servers

    /// Returns `nil` when the address will not parse, which is the one failure
    /// the caller has to show differently: there is no server to attach a
    /// message to yet.
    @discardableResult
    public func addServer(
        address: String,
        name: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) -> ServerTarget? {
        guard let endpoint = EndpointURL.normalise(address) else { return nil }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = ServerTarget(
            name: trimmedName?.isEmpty == false ? trimmedName! : (endpoint.host ?? address),
            endpoint: endpoint,
            username: username?.isEmpty == false ? username : nil,
            createdAt: clock()
        )
        servers.append(target)
        if let password, !password.isEmpty,
           !credentials.setPassword(password, for: target.id) {
            credentialFailureNotice =
                "Couldn't save the password for \(target.name) to your Keychain."
        } else {
            credentialFailureNotice = nil
        }
        scheduleSave()
        return target
    }

    public func deleteServer(id: UUID) {
        servers.removeAll { $0.id == id }
        snapshots[id] = nil
        failures[id] = nil
        trends[id] = nil
        // The password would otherwise outlive the thing it unlocked.
        credentials.removePassword(for: id)
        scheduleSave()
    }

    public func updateSettings(_ newValue: ServerSettings) {
        settings = newValue
        scheduleSave()
    }

    public func password(for id: UUID) -> String? {
        credentials.password(for: id)
    }

    // MARK: - Refresh

    /// Stale numbers, or a server that has never had numbers at all. The
    /// second clause matters after a failed first fetch: `lastRefreshed` is
    /// recorded either way, and without it a server could sit at "not checked
    /// yet" for a whole interval while the store believed it was fresh.
    public func needsRefresh(maxAge: TimeInterval) -> Bool {
        if servers.contains(where: { snapshots[$0.id] == nil }) { return true }
        guard let lastRefreshed else { return true }
        return clock().timeIntervalSince(lastRefreshed) > maxAge
    }

    public func refreshIfStale(maxAge: TimeInterval) async {
        guard needsRefresh(maxAge: maxAge) else { return }
        await refresh()
    }

    /// Fetches every server.
    ///
    /// Reentrancy is refused rather than queued: the panel's on-open refresh
    /// and the background loop can both land here, and two interleaved passes
    /// would double every request and interleave two sets of trend points.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for server in servers {
            guard !Task.isCancelled else { return }
            let request = SnapshotRequest(
                url: server.endpoint,
                username: server.username,
                password: credentials.password(for: server.id)
            )
            do {
                let snapshot = try await source.fetch(request)
                // The MainActor served other work during that `await` — a
                // server deleted while its own fetch was in flight must not
                // come back as an orphaned result.
                guard servers.contains(where: { $0.id == server.id }) else { continue }
                snapshots[server.id] = snapshot
                failures[server.id] = nil
                record(snapshot, for: server.id)
            } catch let error as ServerError {
                guard servers.contains(where: { $0.id == server.id }) else { continue }
                failures[server.id] = error.message
            } catch {
                guard servers.contains(where: { $0.id == server.id }) else { continue }
                // Any other error type would otherwise reach the panel as-is,
                // and a URLError's debug description is not a caption.
                failures[server.id] = "Something went wrong while checking."
            }
        }
        lastRefreshed = clock()
        scheduleSave()
    }

    /// Appends to the ring buffer, dropping the oldest point once full.
    ///
    /// A snapshot with no rate data yet (the agent's first sample after a
    /// restart) is skipped rather than recorded as zero, which would draw a
    /// trough that never happened.
    private func record(_ snapshot: HostSnapshot, for id: UUID) {
        guard let cpu = snapshot.cpuBusy else { return }
        var points = trends[id] ?? []
        points.append(TrendPoint(
            at: clock(),
            cpu: cpu,
            load: snapshot.load1,
            memory: snapshot.memoryFraction * 100
        ))
        if points.count > Self.trendCapacity {
            points.removeFirst(points.count - Self.trendCapacity)
        }
        trends[id] = points
    }

    // MARK: - Derived

    public func alerts(for id: UUID) -> [HostAlert] {
        guard let snapshot = snapshots[id] else { return [] }
        return HostAlerts.evaluate(snapshot)
    }

    /// The worst level across every server, which is what the menu bar shows.
    public var worstAlertLevel: HostAlert.Level? {
        servers.compactMap { alerts(for: $0.id).first?.level }.max()
    }

    /// A server that has a stored snapshot but whose last fetch failed is
    /// still counted as unreachable here: the menu bar should not go calm
    /// because there are old numbers on disk.
    public var hasUnreachableServer: Bool {
        servers.contains { failures[$0.id] != nil }
    }

    /// What the menu bar shows: the first server's CPU, when there is one.
    public var menuBarCPU: Int? {
        guard let first = servers.first,
              let busy = snapshots[first.id]?.cpuBusy,
              failures[first.id] == nil
        else { return nil }
        return Int(busy.rounded())
    }

    // MARK: - Persistence

    private func load() {
        do {
            guard let document = try storage.load(ServerDocument.self, named: filename) else { return }
            servers = document.servers
            snapshots = document.snapshots
            trends = document.trends
            settings = document.settings
            lastRefreshed = document.lastRefreshed
        } catch {
            // PluginStorage kept a .bak beside the file, so nothing is lost —
            // but the user should know why their servers vanished.
            loadFailureNotice = "Couldn't read your servers. A copy was kept as servers.json.bak."
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
        let document = ServerDocument(
            servers: servers,
            snapshots: snapshots,
            trends: trends,
            settings: settings,
            lastRefreshed: lastRefreshed
        )
        do {
            try storage.save(document, named: filename)
            saveFailureNotice = nil
        } catch {
            saveFailureNotice = "Couldn't save your servers. Changes may be lost if Perch quits."
        }
    }
}
