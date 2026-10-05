import AppKit
import Observation
import PerchKit
import SwiftUI

/// While Spotify or Music plays, the desktop becomes a room with a turntable
/// spinning the album.
///
/// Declares `.network` to download Spotify's artwork, and `.media` because it
/// reads what the user is listening to over Apple Events.
@MainActor
@Observable
public final class Spin: PerchPlugin {
    public static let identifier = "org.ahlab.perch.spin"
    public static let displayName = "Spin"
    public static let icon = "record.circle"
    public static let capabilities: Set<PluginCapability> = [.network, .media]

    public let model: SpinModel

    @ObservationIgnored private let source = NowPlayingSource()
    @ObservationIgnored private var desktop: DesktopSceneController?
    @ObservationIgnored private var sleepTokens: [NSObjectProtocol] = []

    public convenience init(context: PluginContext) {
        let runner = NSAppleScriptRunner()
        self.init(
            context: context,
            scenes: SceneCatalog.builtIn,
            artwork: ArtworkFetcher(runner: runner, cacheDirectory: context.storage.url(named: "Artwork")),
            query: ScriptedPlayerQuery(runner: runner)
        )
    }

    /// The testable initializer.
    init(context: PluginContext, scenes: [SceneAsset], artwork: ArtworkProviding, query: PlayerQuerying) {
        model = SpinModel(defaults: context.defaults, scenes: scenes, artworkProvider: artwork, query: query)
    }

    public var panel: AnyView { AnyView(SpinPanelView(model: model)) }

    public var menuBarLabel: MenuBarLabel? {
        guard let event = model.nowPlaying, event.state == .playing, let track = event.track else {
            return MenuBarLabel(systemImage: Self.icon)
        }
        let text = track.artist.isEmpty ? track.title : "\(track.title) – \(track.artist)"
        return MenuBarLabel(systemImage: Self.icon, text: text)
    }

    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            source.onEvent = { [weak model] in model?.receive($0) }
            source.onPing = { [weak model] in model?.refresh($0) }
            source.start()
            model.activate()
            let desktop = DesktopSceneController(model: model)
            desktop.start()
            self.desktop = desktop
            observeSleep()
        } else {
            source.stop()
            desktop?.stop()
            desktop = nil
            for token in sleepTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            sleepTokens = []
            model.reset()
        }
    }

    /// No one is watching a locked or sleeping screen; stop drawing.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        sleepTokens = pairs.map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.isScreenAsleep = asleep }
            }
        }
    }
}
