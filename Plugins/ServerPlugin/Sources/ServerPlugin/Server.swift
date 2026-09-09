import Observation
import PerchKit
import SwiftUI

/// A server's health in the menu bar: CPU, load, memory, swap, disk and
/// network for machines running the `vpsstat` agent, with the things worth
/// worrying about pulled to the top.
///
/// Declares `.network` because it polls each server's HTTP endpoint, and
/// `.credentials` because a server behind basic auth needs a password, which
/// is kept in the Keychain rather than beside the rest of the settings.
@MainActor
@Observable
public final class Server: PerchPlugin {
    public static let identifier = "org.ahlab.perch.server"
    public static let displayName = "Server"
    public static let icon = "server.rack"
    public static let capabilities: Set<PluginCapability> = [.network, .credentials]

    public let store: ServerStore

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public required convenience init(context: PluginContext) {
        self.init(
            context: context,
            source: HTTPSnapshotSource(),
            credentials: KeychainServerCredentials()
        )
    }

    /// The testable initializer. The production path above passes the real
    /// URLSession-backed source and the real Keychain; tests pass fakes.
    public init(
        context: PluginContext,
        source: SnapshotSource,
        credentials: ServerCredentialStore
    ) {
        store = ServerStore(
            storage: context.storage,
            source: source,
            credentials: credentials
        )
    }

    public var panel: AnyView {
        AnyView(ServerPanelView(store: store))
    }

    public var settings: AnyView {
        AnyView(ServerSettingsView(store: store))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape.
    ///
    /// The icon changes rather than the text when something is wrong: a
    /// percentage that has gone stale looks identical to one that is fine, and
    /// the whole point of watching a box is to notice without reading.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: symbol, text: store.menuBarCPU.map { "\($0)%" })
    }

    private var symbol: String {
        if store.hasUnreachableServer { return "exclamationmark.triangle.fill" }
        switch store.worstAlertLevel {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle"
        case nil: return Self.icon
        }
    }

    public var footerActions: [PluginAction] {
        guard !store.servers.isEmpty else { return [] }
        return [
            PluginAction(id: "refresh", title: "Refresh") { [store] in
                Task { await store.refresh() }
            }
        ]
    }

    /// The store debounces its writes; this covers the window between a
    /// refresh landing and the process dying.
    public func flush() { store.saveNow() }

    /// Whether the background refresh loop is live.
    public var isRefreshLoopRunning: Bool { refreshTask != nil }

    /// The host calls this at startup with the stored state, and again on
    /// every toggle. Polling someone's servers is precisely the kind of work a
    /// user expects to stop when they switch a plugin off.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startRefreshing()
        } else {
            stopRefreshing()
        }
    }

    /// Refreshes now and then on the configured interval.
    ///
    /// A `Task` loop rather than a `Timer`: the loop holds only a weak
    /// reference and returns as soon as the plugin is gone, so there is
    /// nothing to tear down from a nonisolated `deinit`. The interval is
    /// re-read every pass so a settings change takes effect at the next wake.
    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let store = self?.store else { return }
                let interval = store.settings.refreshInterval
                if !store.servers.isEmpty {
                    await store.refreshIfStale(maxAge: interval)
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
