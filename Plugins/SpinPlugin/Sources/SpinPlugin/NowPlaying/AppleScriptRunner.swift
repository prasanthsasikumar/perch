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

/// Runs scripts one at a time on a private serial queue: `NSAppleScript` is
/// not thread-safe, so access is serialized, and a slow player must not
/// block the main thread.
final class NSAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.ahlab.perch.spin.applescript")
    private let execute: @Sendable (String) throws -> ScriptValue

    init(execute: @escaping @Sendable (String) throws -> ScriptValue = { try NSAppleScriptRunner.execute($0) }) {
        self.execute = execute
    }

    /// A caller cancelled while its script waits in the queue never sends it,
    /// so disabling Spin stops Apple Events that were already lined up.
    func run(_ source: String) async throws -> ScriptValue {
        let cancelled = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [execute] in
                    guard !cancelled.isSet else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        continuation.resume(returning: try execute(source))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    static func execute(_ source: String) throws -> ScriptValue {
        guard let script = NSAppleScript(source: source) else { throw ScriptError.failed(0) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            throw code == -1743 ? ScriptError.notPermitted : ScriptError.failed(code)
        }
        return value(of: result)
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

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

enum PlayerProcess {
    /// An Apple Event to a quit app launches it, so every script is gated on this.
    static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }
}
