import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    /// No default shortcut — unset until the user records one in Settings.
    static let openPerch = Self("openPerch")
}

@MainActor
@Observable
final class AppState {
    var isMenuPresented = false

    init() {
        KeyboardShortcuts.onKeyUp(for: .openPerch) { [weak self] in
            self?.isMenuPresented.toggle()
        }
    }
}
