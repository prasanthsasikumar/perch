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
    private let installer: HelperInstalling

    init(reader: SleepStateReading, helper: SleepHelperClient, installer: HelperInstalling) {
        self.reader = reader
        self.helper = helper
        self.installer = installer
        isSleepDisabled = reader.isSleepDisabled()
    }

    convenience init() {
        self.init(
            reader: IOKitSleepStateReader(),
            helper: XPCSleepHelperClient(),
            installer: CompanionInstaller()
        )
    }

    var tooltip: String {
        switch status {
        case .needsApproval:
            "Click again. If nothing changes, allow Perch Keep Awake in System Settings → Login Items"
        case .failed(let message):
            message
        case .ready:
            isSleepDisabled ? "Staying awake with lid closed" : "Keep awake with lid closed"
        }
    }

    /// Called at launch and whenever the panel opens.
    func refresh() {
        isSleepDisabled = reader.isSleepDisabled()
    }

    func toggle() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await setSleepDisabled(!isSleepDisabled)
            status = .ready
        } catch SleepHelperFailure.unreachable {
            // The sandbox will not tell Perch whether the helper is
            // registered; failing to reach it is how we find out.
            installer.install()
            status = .needsApproval
        } catch {
            status = .failed(error.localizedDescription)
        }
        isSleepDisabled = reader.isSleepDisabled()
    }

    /// The helper exits when idle, and a call that lands as it is exiting
    /// loses its connection. launchd starts a fresh helper for the next one,
    /// so one more attempt tells a helper caught exiting from one that is
    /// not there.
    private func setSleepDisabled(_ disabled: Bool) async throws {
        do {
            try await helper.setSleepDisabled(disabled)
        } catch SleepHelperFailure.unreachable {
            try await helper.setSleepDisabled(disabled)
        }
    }
}
