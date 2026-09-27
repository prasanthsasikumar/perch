import Foundation

/// What the helper runs. Pure, so it can be tested without being root.
enum PmsetCommand {
    static let executable = "/usr/bin/pmset"

    static func arguments(disabled: Bool) -> [String] {
        ["-a", "disablesleep", disabled ? "1" : "0"]
    }

    /// `pmset` can fail without saying why; an empty tooltip helps nobody.
    static func failureMessage(status: Int32, stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "pmset exited with status \(status)" : trimmed
    }
}
