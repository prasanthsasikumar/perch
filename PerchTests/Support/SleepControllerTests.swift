@testable import Perch
import XCTest

@MainActor
private final class FakeReader: SleepStateReading {
    var value = false
    func isSleepDisabled() -> Bool { value }
}

@MainActor
private final class FakeHelper: SleepHelperClient {
    var calls: [Bool] = []
    var error: Error?
    /// Thrown by the next call only, then forgotten.
    var errorOnce: Error?
    /// What a successful call does to the system. `nil` leaves it untouched.
    var onSuccess: ((Bool) -> Void)?
    /// Held open until the test resumes it, to keep a call in flight.
    var gate: CheckedContinuation<Void, Never>?
    var holdsCalls = false

    func setSleepDisabled(_ disabled: Bool) async throws {
        calls.append(disabled)
        if holdsCalls {
            await withCheckedContinuation { gate = $0 }
        }
        if let errorOnce {
            self.errorOnce = nil
            throw errorOnce
        }
        if let error { throw error }
        onSuccess?(disabled)
    }
}

@MainActor
private final class FakeInstaller: HelperInstalling {
    var installs = 0
    func install() { installs += 1 }
}

@MainActor
final class SleepControllerTests: XCTestCase {
    private var reader: FakeReader!
    private var helper: FakeHelper!
    private var installer: FakeInstaller!

    override func setUp() async throws {
        reader = FakeReader()
        helper = FakeHelper()
        installer = FakeInstaller()
        helper.onSuccess = { [reader] in reader?.value = $0 }
    }

    private func makeController() -> SleepController {
        SleepController(reader: reader, helper: helper, installer: installer)
    }

    func testStartsFromTheSystemState() {
        reader.value = true
        XCTAssertTrue(makeController().isSleepDisabled)
    }

    func testToggleOnThenOff() async {
        let controller = makeController()

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true])
        XCTAssertTrue(controller.isSleepDisabled)
        XCTAssertEqual(controller.status, .ready)

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true, false])
        XCTAssertFalse(controller.isSleepDisabled)
    }

    func testStateComesFromReaderNotRequest() async {
        helper.onSuccess = nil
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(helper.calls, [true])
        XCTAssertFalse(controller.isSleepDisabled)
    }

    func testHelperFailureIsReportedAndStateUnchanged() async {
        helper.error = SleepHelperFailure.rejected("pmset: must be root")
        let controller = makeController()

        await controller.toggle()

        XCTAssertFalse(controller.isSleepDisabled)
        XCTAssertEqual(controller.status, .failed("pmset: must be root"))
        XCTAssertEqual(controller.tooltip, "pmset: must be root")
    }

    func testFailureClearsOnNextSuccess() async {
        helper.error = SleepHelperFailure.rejected("interrupted")
        let controller = makeController()
        await controller.toggle()

        helper.error = nil
        await controller.toggle()

        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    /// Perch is sandboxed and cannot ask whether the helper is registered;
    /// an unreachable helper is how it finds out.
    func testUnreachableHelperRunsTheInstaller() async {
        helper.error = SleepHelperFailure.unreachable("Couldn't communicate with a helper application.")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(installer.installs, 1)
        XCTAssertEqual(controller.status, .needsApproval)
        XCTAssertFalse(controller.isSleepDisabled)
        XCTAssertEqual(controller.tooltip, "Allow Perch Keep Awake in System Settings → Login Items, then click again")
    }

    /// The helper exits when idle. A click that lands as it is exiting loses
    /// its connection; launchd starts a fresh helper for the second attempt.
    func testAHelperCaughtExitingIsTriedAgain() async {
        helper.errorOnce = SleepHelperFailure.unreachable("connection interrupted")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(helper.calls, [true, true])
        XCTAssertEqual(installer.installs, 0)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testWorksOnTheClickAfterApproval() async {
        helper.error = SleepHelperFailure.unreachable("no helper")
        let controller = makeController()
        await controller.toggle()

        helper.error = nil
        await controller.toggle()

        XCTAssertEqual(installer.installs, 1)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testARejectionDoesNotRunTheInstaller() async {
        helper.error = SleepHelperFailure.rejected("pmset exited with status 71")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(installer.installs, 0)
        XCTAssertEqual(controller.status, .failed("pmset exited with status 71"))
    }

    func testRefreshPicksUpAChangeMadeOutsidePerch() {
        let controller = makeController()
        reader.value = true

        controller.refresh()

        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testToggleWhileBusyIsIgnored() async {
        helper.holdsCalls = true
        let controller = makeController()

        let first = Task { await controller.toggle() }
        while helper.gate == nil { await Task.yield() }
        XCTAssertTrue(controller.isBusy)

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true])

        helper.gate?.resume()
        await first.value
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testTooltipsForOnAndOff() async {
        let controller = makeController()
        XCTAssertEqual(controller.tooltip, "Keep awake with lid closed")

        await controller.toggle()
        XCTAssertEqual(controller.tooltip, "Staying awake with lid closed")
    }
}
