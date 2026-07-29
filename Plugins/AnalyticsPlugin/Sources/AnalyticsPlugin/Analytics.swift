import Observation
import PerchKit
import SwiftUI

/// Google Analytics in the menu bar: today's active users on the property you
/// care about, and the week's shape one click away.
///
/// Declares `.network` and `.credentials`. It talks to Google, and it holds a
/// service-account key — the first plugin in Perch to do either.
@MainActor
@Observable
public final class Analytics: PerchPlugin {
    public static let identifier = "org.ahlab.perch.analytics"
    public static let displayName = "Analytics"
    public static let icon = "chart.line.uptrend.xyaxis"
    public static let capabilities: Set<PluginCapability> = [.network, .credentials]

    /// Half-hourly. GA4 does not update fast enough to reward anything
    /// tighter, and the panel refetches on open regardless.
    static let refreshInterval: TimeInterval = 30 * 60

    public let store: AnalyticsStore

    private var refreshTask: Task<Void, Never>?

    public required init(context: PluginContext) {
        store = AnalyticsStore(
            storage: context.storage,
            credentials: KeychainCredentialStore(
                service: Self.identifier,
                account: "serviceAccount"
            )
        )
        startRefreshing()
    }

    public var panel: AnyView {
        AnyView(AnalyticsPanelView(store: store))
    }

    public var settings: AnyView {
        AnyView(AnalyticsSettingsView(store: store))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape,
    /// with the number appearing once there is one.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(
            systemImage: Self.icon,
            text: store.menuBarUsers.map { Formatting.compact($0) }
        )
    }

    public var footerActions: [PluginAction] {
        guard store.isConfigured, !store.properties.isEmpty else { return [] }
        return [
            PluginAction(id: "refresh", title: "Refresh") { [store] in
                Task { await store.refresh() }
            }
        ]
    }

    /// The cache is written on every change already; this covers the window
    /// between a refresh landing and the process dying.
    public func flush() { store.saveNow() }

    /// Refreshes now and then every half hour.
    ///
    /// A `Task` loop rather than a `Timer`: the loop holds only a weak
    /// reference and returns as soon as the plugin is gone, so there is
    /// nothing to tear down from a nonisolated `deinit`.
    private func startRefreshing() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let store = self?.store else { return }
                await store.refreshIfStale(maxAge: Self.refreshInterval)
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }
}
