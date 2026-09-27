import Foundation
import ServiceManagement

struct SleepHelperError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

@MainActor
protocol SleepHelperClient {
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
                continuation.resume(throwing: SleepHelperError(error.localizedDescription))
            }
            guard let helper = proxy as? SleepHelperProtocol else {
                continuation.resume(throwing: SleepHelperError("The helper did not respond"))
                return
            }
            helper.setSleepDisabled(disabled) { message in
                if let message {
                    continuation.resume(throwing: SleepHelperError(message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum HelperRegistrationState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
}

@MainActor
protocol HelperRegistering {
    var state: HelperRegistrationState { get }
    func register() throws
    func openApprovalSettings()
}

struct DaemonRegistration: HelperRegistering {
    private var service: SMAppService {
        .daemon(plistName: SleepHelper.daemonPlistName)
    }

    var state: HelperRegistrationState {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
