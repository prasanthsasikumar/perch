import Observation
import PerchKit
import SwiftUI

/// How busy a place is right now, in the menu bar: type a place the way you
/// would search for it on Google, and its live busyness and today's popular
/// times turn up in the panel.
///
/// Declares `.network` because it loads Google search pages. Nothing is
/// stored with Google and nothing is signed in to.
@MainActor
@Observable
public final class Busy: PerchPlugin {
    public static let identifier = "org.ahlab.perch.busy"
    public static let displayName = "Busy"
    public static let icon = "person.3.fill"
    public static let capabilities: Set<PluginCapability> = [.network]

    public let store: BusyStore

    /// Non-nil only on the production path. Tests inject a fake source and
    /// get no webview.
    public private(set) var session: GoogleSession?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public required convenience init(context: PluginContext) {
        let session = GoogleSession()
        let source = RoutingBusynessSource(
            google: GoogleBusynessSource(session: session),
            planetFitness: PlanetFitnessBusynessSource(session: session)
        )
        self.init(context: context, source: source, starterPlaces: [PlanetFitness.sampleClub])
        self.session = session
    }

    /// The testable initializer. The production path above passes the real
    /// WKWebView-backed sources; tests pass a fake.
    public init(context: PluginContext, source: BusynessSource, starterPlaces: [String] = []) {
        store = BusyStore(storage: context.storage, source: source, starterPlaces: starterPlaces)
    }

    public var panel: AnyView {
        AnyView(BusyPanelView(store: store))
    }

    public var settings: AnyView {
        AnyView(BusySettingsView(store: store))
    }

    /// Always contributes the icon so the menu bar item keeps a stable shape,
    /// with the first place's live figure appearing once there is one.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: Self.icon, text: store.menuBarPercent.map { "\($0)%" })
    }

    public var footerActions: [PluginAction] {
        guard !store.places.isEmpty else { return [] }
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
    /// every toggle. Loading Google pages in the background is precisely the
    /// kind of work a user expects to stop when they switch a plugin off.
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
                if !store.places.isEmpty {
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
