import Foundation

extension String {
    /// Trims whitespace and caps the string at `maxLength` characters,
    /// appending an ellipsis when it was cut.
    func truncatedForMenuBar(to maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength))
            .trimmingCharacters(in: .whitespaces) + "…"
    }
}
