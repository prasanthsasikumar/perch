import Foundation

/// Calls `onIdle` after a quiet spell, so that nothing root stays resident.
///
/// Never while a request is in flight: a helper that exits mid-call takes
/// the reply with it. Main queue only.
final class IdleExit {
    private let delay: TimeInterval
    private let onIdle: () -> Void
    private var inFlight = 0
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval, onIdle: @escaping () -> Void) {
        self.delay = delay
        self.onIdle = onIdle
    }

    /// Restarts the clock.
    func touch() {
        pending?.cancel()
        pending = nil
        guard inFlight == 0 else { return }
        let item = DispatchWorkItem { [onIdle] in onIdle() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func begin() {
        inFlight += 1
        touch()
    }

    func end() {
        inFlight = max(0, inFlight - 1)
        touch()
    }
}
