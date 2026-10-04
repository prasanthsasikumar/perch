import AppKit
import Foundation

enum ScriptValue: Equatable, Sendable {
    case text(String)
    case data(Data)
    case none
}

enum ScriptError: Error, Equatable {
    /// The user said no to "Perch wants to control …" (errAEEventNotPermitted).
    case notPermitted
    case failed(Int)
}

protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async throws -> ScriptValue
}

/// Runs scripts one at a time on a private serial queue. `NSAppleScript` is
/// not thread-safe, but is fine confined to a single thread, and a slow
/// player must not block the main thread.
final class NSAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.ahlab.perch.spin.applescript")

    func run(_ source: String) async throws -> ScriptValue {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: ScriptError.failed(0))
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    continuation.resume(throwing: code == -1743 ? ScriptError.notPermitted : ScriptError.failed(code))
                    return
                }
                continuation.resume(returning: Self.value(of: result))
            }
        }
    }

    private static func value(of descriptor: NSAppleEventDescriptor) -> ScriptValue {
        switch descriptor.descriptorType {
        case DescType(typeNull):
            return .none
        case DescType(typeUnicodeText), DescType(typeUTF8Text), DescType(typeChar):
            return .text(descriptor.stringValue ?? "")
        default:
            return descriptor.data.isEmpty ? .none : .data(descriptor.data)
        }
    }
}

enum PlayerProcess {
    /// An Apple Event to a quit app launches it, so every script is gated on this.
    static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }
}
