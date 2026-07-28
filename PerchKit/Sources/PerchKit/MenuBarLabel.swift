import Foundation

/// What a plugin wants shown in the menu bar.
///
/// Deliberately a value type rather than a `View`: the host owns menu bar
/// layout and truncation, so a plugin cannot smuggle arbitrary UI up there.
public struct MenuBarLabel: Equatable, Sendable {
    /// SF Symbol name.
    public let systemImage: String
    /// Accompanying text, or `nil` for icon only.
    public let text: String?

    public init(systemImage: String, text: String? = nil) {
        self.systemImage = systemImage
        self.text = text
    }
}
