import PerchKit

/// Turns the selected plugin's contribution into what actually gets drawn,
/// applying the user's menu bar preferences.
///
/// Kept separate from the view so the rules are testable: a plugin's label is
/// the most visible thing Perch does, and it is the easiest to get subtly wrong.
enum MenuBarLabelResolver {
    /// - Returns: the label to draw, or `nil` when no plugin contributed one —
    ///   in which case the caller falls back to Perch's own icon.
    static func resolve(
        label: MenuBarLabel?,
        showTitle: Bool,
        truncationLength: Int
    ) -> MenuBarLabel? {
        guard let label else { return nil }
        guard showTitle, let text = label.text else {
            return MenuBarLabel(systemImage: label.systemImage, text: nil)
        }
        return MenuBarLabel(
            systemImage: label.systemImage,
            text: text.truncatedForMenuBar(to: truncationLength)
        )
    }
}
