import AppKit
import Observation
import PerchKit

/// Everything Spin knows, and every decision it makes, minus the window.
@MainActor
@Observable
public final class SpinModel {
    public enum ArtworkStatus: Equatable, Sendable {
        case none
        case loading
        case loaded
        case notPermitted
    }

    public private(set) var nowPlaying: PlayerEvent?
    public private(set) var artwork: NSImage?
    public private(set) var artworkStatus: ArtworkStatus = .none
    private(set) var phase: SceneVisibility.Phase = .hidden
    private(set) var motion = SpinMotion()
    /// Whether the record's animation clock needs to tick: spinning, or still
    /// easing to a stop.
    public private(set) var isAnimating = false
    /// Set by the plugin while the display sleeps or the session is locked.
    public var isScreenAsleep = false

    let scenes: [SceneAsset]

    public var selectedSceneID: String {
        didSet { defaults.set(selectedSceneID, for: Key.scene) }
    }

    /// Off until the user turns it on: this is what triggers the Automation
    /// prompt and takes over the desktop, so neither happens unasked.
    public var showsScene: Bool {
        didSet {
            defaults.set(showsScene, for: Key.showsScene)
            guard showsScene != oldValue else { return }
            guard showsScene else {
                cancelScripting()
                return
            }
            if let track = nowPlaying?.track { loadArtwork(for: track) }
            prime()
        }
    }

    var selectedScene: SceneAsset? {
        scenes.first { $0.id == selectedSceneID } ?? scenes.first
    }

    var wantsWindow: Bool {
        showsScene && phase != .hidden && selectedScene != nil
    }

    private enum Key {
        static let scene = "scene"
        static let showsScene = "showsScene"
    }

    @ObservationIgnored private let defaults: PluginDefaults
    @ObservationIgnored private let artworkProvider: ArtworkProviding
    @ObservationIgnored private let query: PlayerQuerying
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tracker = NowPlayingTracker()
    @ObservationIgnored private var lastPlayingAt: Date?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var queryTasks: [Task<Void, Never>] = []

    init(
        defaults: PluginDefaults,
        scenes: [SceneAsset],
        artworkProvider: ArtworkProviding,
        query: PlayerQuerying,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.scenes = scenes
        self.artworkProvider = artworkProvider
        self.query = query
        self.now = now
        selectedSceneID = defaults.string(Key.scene) ?? scenes.first?.id ?? ""
        showsScene = defaults.bool(Key.showsScene, default: false)
    }

    // MARK: Inputs

    public func receive(_ event: PlayerEvent) {
        let wasPlaying = nowPlaying?.state == .playing
        guard tracker.apply(event) else { return }
        let current = tracker.current
        let previousTrack = nowPlaying?.track
        nowPlaying = current

        let time = now()
        // Review Focus 1: stamp the end of playback too, so the linger
        // counts from when the music stopped.
        if current?.state == .playing || wasPlaying { lastPlayingAt = time }

        // A stop carries no track; the last art stays up while the scene lingers.
        if let track = current?.track, track != previousTrack {
            loadArtwork(for: track)
        }

        let isPlaying = current?.state == .playing
        motion.setPlaying(isPlaying, at: time)
        updateAnimating(isPlaying)
        reevaluate()
    }

    /// A player posted a notification we could not read; ask it directly.
    public func refresh(_ player: Player) {
        guard showsScene else { return }
        let query = query
        queryTasks.append(Task { [weak self] in
            guard let event = await query.event(for: player) else { return }
            self?.receive(event)
        })
    }

    /// Called when the plugin is enabled.
    public func activate() { prime() }

    /// Called when the plugin is disabled: forget everything, cancel everything.
    public func reset() {
        cancelScripting()
        lingerTask?.cancel()
        settleTask?.cancel()
        tracker = NowPlayingTracker()
        nowPlaying = nil
        artwork = nil
        artworkStatus = .none
        lastPlayingAt = nil
        motion = SpinMotion()
        isAnimating = false
        phase = .hidden
    }

    func reevaluate() {
        phase = SceneVisibility.phase(state: nowPlaying?.state, lastPlayingAt: lastPlayingAt, now: now())
        scheduleLinger()
    }

    /// Test hook: wait for in-flight artwork and query work.
    func settle() async {
        for task in queryTasks { await task.value }
        await artworkTask?.value
    }

    // MARK: Work

    /// Stops every Apple Events request in flight or queued.
    private func cancelScripting() {
        artworkTask?.cancel()
        queryTasks.forEach { $0.cancel() }
        queryTasks = []
        if artworkStatus == .loading { artworkStatus = .none }
    }

    private func prime() {
        guard showsScene else { return }
        for player in Player.allCases { refresh(player) }
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        artwork = nil
        guard showsScene else {
            artworkStatus = .none
            return
        }
        artworkStatus = .loading
        let provider = artworkProvider
        artworkTask = Task { [weak self] in
            let result = await provider.artwork(for: track)
            guard !Task.isCancelled, let self, self.nowPlaying?.track == track else { return }
            switch result {
            case .image(let data):
                self.artwork = NSImage(data: data)
                self.artworkStatus = self.artwork == nil ? .none : .loaded
            case .none:
                self.artworkStatus = .none
            case .notPermitted:
                self.artworkStatus = .notPermitted
            }
        }
    }

    private func updateAnimating(_ isPlaying: Bool) {
        settleTask?.cancel()
        if isPlaying {
            isAnimating = true
            return
        }
        guard isAnimating else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SpinMotion.spinDown + 0.1))
            guard !Task.isCancelled, let self, self.nowPlaying?.state != .playing else { return }
            self.isAnimating = false
        }
    }

    private func scheduleLinger() {
        lingerTask?.cancel()
        guard phase == .resting, let lastPlayingAt else { return }
        let delay = max(0, lastPlayingAt.addingTimeInterval(SceneVisibility.linger).timeIntervalSince(now()))
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.1))
            guard !Task.isCancelled else { return }
            self?.reevaluate()
        }
    }
}
