import Observation
import PerchKit
import SwiftUI

/// Web analytics in the menu bar: today's active users on the property you
/// care about, and the week's shape one click away.
///
/// Reads from Google Analytics or PostHog, whichever the user picks in
/// Settings. Each source keeps its own key, sites and cache, so switching is
/// never destructive; only the selected one is shown and refreshed.
///
/// Declares `.network` and `.credentials`. It talks to Google or PostHog, and
/// it holds a service-account key or a personal API key.
@MainActor
@Observable
public final class Analytics: PerchPlugin {
    public static let identifier = "org.ahlab.perch.analytics"
    public static let displayName = "Analytics"
    public static let icon = "chart.line.uptrend.xyaxis"
    public static let summary = "Your Google Analytics or PostHog numbers, a click away."
    public static let capabilities: Set<PluginCapability> = [.network, .credentials]

    /// Half-hourly. GA4 does not update fast enough to reward anything
    /// tighter, and the panel refetches on open regardless. Public so it can
    /// serve as the default argument of the testable initializer below.
    public static let defaultRefreshInterval: TimeInterval = 30 * 60

    /// The Google Analytics store. Named plainly because it came first and
    /// the tests and host reach for it by this name.
    public let store: AnalyticsStore
    /// `nil` only under tests that build the plugin with GA alone.
    public let postHogStore: AnalyticsStore?
    private let refreshInterval: TimeInterval
    @ObservationIgnored private let defaults: PluginDefaults?

    /// Which source the panel, menu bar and refresh loop use.
    public var source: AnalyticsSource {
        didSet {
            guard source != oldValue else { return }
            defaults?.set(source.rawValue, for: AnalyticsSource.defaultsKey)
            // The loop sleeps for half an hour between passes; without a
            // nudge the newly chosen source would sit unfetched until then.
            if refreshTask != nil {
                startRefreshing()
            }
        }
    }

    /// The store for the selected source. Falls back to GA if PostHog was
    /// chosen but this plugin was built without a PostHog store.
    public var activeStore: AnalyticsStore {
        source == .postHog ? (postHogStore ?? store) : store
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// The Keychain account names. Same service, so both items show up
    /// together under the plugin in Keychain Access.
    static let googleKeychainAccount = "serviceAccount"
    static let postHogKeychainAccount = "postHogPersonalAPIKey"

    public required convenience init(context: PluginContext) {
        self.init(
            store: AnalyticsStore(
                storage: context.storage,
                credentials: KeychainCredentialStore(
                    service: Self.identifier,
                    account: Self.googleKeychainAccount
                )
            ),
            postHogStore: AnalyticsStore(
                postHogStorage: context.storage,
                credentials: KeychainCredentialStore(
                    service: Self.identifier,
                    account: Self.postHogKeychainAccount
                )
            ),
            defaults: context.defaults
        )
    }

    /// The testable initializer. Tests pass an in-memory store — the
    /// production path is the only place a `KeychainCredentialStore` is
    /// constructed, so tests never touch the Keychain — and, when the
    /// refresh loop itself is under test, a short `refreshInterval` so the
    /// loop can be observed without a real half-hour wait.
    public init(
        store: AnalyticsStore,
        postHogStore: AnalyticsStore? = nil,
        defaults: PluginDefaults? = nil,
        refreshInterval: TimeInterval = Analytics.defaultRefreshInterval
    ) {
        self.store = store
        self.postHogStore = postHogStore
        self.defaults = defaults
        self.refreshInterval = refreshInterval
        // GA is the default because every install before PostHog existed was
        // a GA install, and it must come back up the way it was left.
        self.source = defaults?.string(AnalyticsSource.defaultsKey)
            .flatMap(AnalyticsSource.init(rawValue:)) ?? .googleAnalytics
    }

    public var panel: AnyView {
        AnyView(AnalyticsRootPanel(plugin: self))
    }

    public var settings: AnyView {
        AnyView(AnalyticsRootSettings(plugin: self))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape,
    /// with the number appearing once there is one.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(
            systemImage: Self.icon,
            text: activeStore.menuBarUsers.map { Formatting.compact($0) }
        )
    }

    public var footerActions: [PluginAction] {
        let store = activeStore
        guard store.isConfigured, !store.properties.isEmpty else { return [] }
        return [
            PluginAction(id: "refresh", title: "Refresh") { [store] in
                Task { await store.refresh() }
            }
        ]
    }

    /// The cache is written on every change already; this covers the window
    /// between a refresh landing and the process dying.
    public func flush() {
        store.saveNow()
        postHogStore?.saveNow()
    }

    /// Whether the background refresh loop is live. Named distinctly from
    /// `AnalyticsStore.isRefreshing`, which means something different (a
    /// fetch is in flight, and it drives the panel spinner) and would
    /// otherwise collide with this.
    public var isRefreshLoopRunning: Bool { refreshTask != nil }

    /// The host calls this at startup with the stored state, and again on every
    /// toggle. Until this existed, a switched-off Analytics went on
    /// authenticating to Google and fetching GA4 numbers every half hour.
    /// Only the selected source is ever fetched.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startRefreshing()
        } else {
            stopRefreshing()
        }
    }

    /// Refreshes now and then every half hour.
    ///
    /// A `Task` loop rather than a `Timer`: the loop holds only a weak
    /// reference and returns as soon as the plugin is gone, so there is
    /// nothing to tear down from a nonisolated `deinit`.
    private func startRefreshing() {
        refreshTask?.cancel()
        let refreshInterval = refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Read every pass, so a source switch is followed even if the
                // nudge in `source.didSet` was missed.
                guard let store = self?.activeStore else { return }
                await store.refreshIfStale(maxAge: refreshInterval)
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
