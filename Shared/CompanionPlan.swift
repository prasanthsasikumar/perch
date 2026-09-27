import Foundation

/// What the companion app does, as decisions apart from the system calls
/// that carry them out.
enum CompanionPlan {
    /// `SMAppService.Status`, without the framework.
    enum Registration: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
    }

    enum Outcome: Equatable {
        /// Open Login Items and say nothing: the first-run case.
        case askForApproval
        /// Allowed, yet Perch could not reach it.
        case explainNotResponding
        /// Registering was refused, as it is for a helper that has been
        /// switched off in Login Items.
        case explainNotAllowed

        var message: String? {
            switch self {
            case .askForApproval:
                nil
            case .explainNotResponding:
                "Keep Awake is allowed but is not responding. In System Settings → Login Items, "
                    + "switch Perch Keep Awake off and on again, then click the cup in Perch."
            case .explainNotAllowed:
                "In System Settings → Login Items, switch on Perch Keep Awake, "
                    + "then click the cup in Perch."
            }
        }
    }

    /// Only a helper that is not registered. An enabled one is never
    /// unregistered to "repair" it: macOS then marks it disabled, and a
    /// helper that was slow to answer becomes one that needs approving
    /// all over again.
    static func shouldRegister(_ registration: Registration) -> Bool {
        registration == .notRegistered
    }

    /// Perch only runs the companion when it could not reach the helper, so
    /// every outcome sends the user somewhere. There is no silent one.
    static func outcome(for registration: Registration) -> Outcome {
        switch registration {
        case .requiresApproval: .askForApproval
        case .enabled: .explainNotResponding
        case .notRegistered: .explainNotAllowed
        }
    }
}
