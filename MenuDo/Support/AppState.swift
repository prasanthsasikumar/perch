import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    /// No default shortcut — unset until the user records one in Settings.
    static let openMenuDo = Self("openMenuDo")
}

@MainActor
@Observable
final class AppState {
    var isMenuPresented = false

    init() {
        KeyboardShortcuts.onKeyUp(for: .openMenuDo) { [weak self] in
            self?.isMenuPresented.toggle()
        }
    }
}
