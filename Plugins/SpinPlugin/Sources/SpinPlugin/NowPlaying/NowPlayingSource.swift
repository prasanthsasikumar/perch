import AppKit

/// Listens to both players' distributed notifications, and to them quitting.
///
/// Receiving a distributed notification needs no permission and works from
/// the sandbox. A notification whose payload does not parse (for example if
/// the sandbox strips userInfo) is passed on as a ping, so the model can ask
/// the player directly.
@MainActor
final class NowPlayingSource {
    var onEvent: ((PlayerEvent) -> Void)?
    var onPing: ((Player) -> Void)?

    private var distributedTokens: [NSObjectProtocol] = []
    private var workspaceToken: NSObjectProtocol?

    func start() {
        guard distributedTokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            let token = center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let event = PlayerNotification.parse(name: note.name, userInfo: note.userInfo)
                MainActor.assumeIsolated {
                    if let event { self?.onEvent?(event) } else { self?.onPing?(player) }
                }
            }
            distributedTokens.append(token)
        }
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = Player.allCases.first(where: { $0.bundleIdentifier == app?.bundleIdentifier }) else { return }
            MainActor.assumeIsolated {
                self?.onEvent?(PlayerEvent(player: player, state: .stopped, track: nil))
            }
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for token in distributedTokens { center.removeObserver(token) }
        distributedTokens = []
        if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }
        workspaceToken = nil
    }
}
