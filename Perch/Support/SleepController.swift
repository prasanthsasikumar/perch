import Foundation
import Observation

/// The keep-awake toggle: `pmset -a disablesleep`, without the Terminal.
///
/// Holds no setting of its own. `isSleepDisabled` is whatever the system
/// last reported, so the button stays truthful when the setting is changed
/// from Terminal, and a helper that claims success cannot make it lie.
@MainActor
@Observable
final class SleepController {
    enum Status: Equatable {
        case ready
        case needsApproval
        case failed(String)
    }

    private(set) var isSleepDisabled: Bool
    private(set) var status: Status = .ready
    private(set) var isBusy = false

    private let reader: SleepStateReading
    private let helper: SleepHelperClient
    private let registration: HelperRegistering

    init(reader: SleepStateReading, helper: SleepHelperClient, registration: HelperRegistering) {
        self.reader = reader
        self.helper = helper
        self.registration = registration
        isSleepDisabled = reader.isSleepDisabled()
    }

    convenience init() {
        self.init(
            reader: IOKitSleepStateReader(),
            helper: XPCSleepHelperClient(),
            registration: DaemonRegistration()
        )
    }

    var tooltip: String {
        switch status {
        case .needsApproval:
            "Allow Perch in System Settings → Login Items"
        case .failed(let message):
            message
        case .ready:
            isSleepDisabled ? "Staying awake with lid closed" : "Keep awake with lid closed"
        }
    }

    /// Called at launch and whenever the panel opens.
    func refresh() {
        isSleepDisabled = reader.isSleepDisabled()
        // The user may have approved the helper since we last looked.
        if status == .needsApproval, registration.state == .enabled {
            status = .ready
        }
    }

    func toggle() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        guard ensureHelperIsUsable() else { return }

        do {
            try await helper.setSleepDisabled(!isSleepDisabled)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
        isSleepDisabled = reader.isSleepDisabled()
    }

    /// Registers the helper on first use. Returns `false`, with `status`
    /// explaining why, when the helper cannot be called yet.
    private func ensureHelperIsUsable() -> Bool {
        switch registration.state {
        case .enabled:
            return true
        case .requiresApproval:
            askForApproval()
            return false
        case .notRegistered:
            do {
                try registration.register()
            } catch {
                // `register()` throws while approval is pending; only a
                // throw that leaves us anywhere else is a real failure.
                guard registration.state == .requiresApproval else {
                    status = .failed(error.localizedDescription)
                    return false
                }
            }
            if registration.state == .enabled { return true }
            if registration.state == .requiresApproval {
                askForApproval()
            } else {
                status = .failed("The helper could not be registered")
            }
            return false
        }
    }

    private func askForApproval() {
        status = .needsApproval
        registration.openApprovalSettings()
    }
}
