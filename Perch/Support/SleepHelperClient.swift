import AppKit
import Foundation

enum SleepHelperFailure: LocalizedError, Equatable {
    /// The connection itself failed: the helper is not registered, not yet
    /// approved, or gone.
    case unreachable(String)
    /// The helper answered, and the answer was no.
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let message), .rejected(let message): message
        }
    }
}

@MainActor
protocol SleepHelperClient {
    /// Throws `SleepHelperFailure`.
    func setSleepDisabled(_ disabled: Bool) async throws
}

/// One connection per call. The helper exits when idle, so a connection kept
/// around would only ever be found invalidated.
struct XPCSleepHelperClient: SleepHelperClient {
    func setSleepDisabled(_ disabled: Bool) async throws {
        let connection = NSXPCConnection(
            machServiceName: SleepHelper.machServiceName, options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        // Refuse to talk to anything that is not our own helper.
        connection.setCodeSigningRequirement(SleepHelper.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        // Exactly one of the error handler and the reply is ever called.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: SleepHelperFailure.unreachable(error.localizedDescription))
            }
            guard let helper = proxy as? SleepHelperProtocol else {
                continuation.resume(throwing: SleepHelperFailure.unreachable("The helper did not respond"))
                return
            }
            helper.setSleepDisabled(disabled) { message in
                if let message {
                    continuation.resume(throwing: SleepHelperFailure.rejected(message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
protocol HelperInstalling {
    func install()
}

/// Perch is sandboxed, and the sandbox refuses to let it register a daemon
/// (`deny job-creation`). So the helper belongs to a small companion app
/// inside the bundle, which is not sandboxed and does nothing but register
/// it, ask for approval if that is needed, and quit.
struct CompanionInstaller: HelperInstalling {
    func install() {
        let companion = Bundle.main.bundleURL
            .appending(path: SleepHelper.companionPath, directoryHint: .isDirectory)
        NSWorkspace.shared.openApplication(
            at: companion, configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
