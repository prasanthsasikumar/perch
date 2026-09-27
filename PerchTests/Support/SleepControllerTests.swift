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
        if let error { throw error }
        onSuccess?(disabled)
    }
}

@MainActor
private final class FakeRegistration: HelperRegistering {
    var state: HelperRegistrationState = .enabled
    var stateAfterRegister: HelperRegistrationState = .enabled
    var registerError: Error?
    var registerCalls = 0
    var openedSettings = 0

    func register() throws {
        registerCalls += 1
        state = stateAfterRegister
        if let registerError { throw registerError }
    }

    func openApprovalSettings() { openedSettings += 1 }
}

@MainActor
final class SleepControllerTests: XCTestCase {
    private var reader: FakeReader!
    private var helper: FakeHelper!
    private var registration: FakeRegistration!

    override func setUp() async throws {
        reader = FakeReader()
        helper = FakeHelper()
        registration = FakeRegistration()
        helper.onSuccess = { [reader] in reader?.value = $0 }
    }

    private func makeController() -> SleepController {
        SleepController(reader: reader, helper: helper, registration: registration)
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
        helper.error = SleepHelperError("pmset: must be root")
        let controller = makeController()

        await controller.toggle()

        XCTAssertFalse(controller.isSleepDisabled)
        XCTAssertEqual(controller.status, .failed("pmset: must be root"))
        XCTAssertEqual(controller.tooltip, "pmset: must be root")
    }

    func testFailureClearsOnNextSuccess() async {
        helper.error = SleepHelperError("interrupted")
        let controller = makeController()
        await controller.toggle()

        helper.error = nil
        await controller.toggle()

        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testFirstToggleRegistersTheHelper() async {
        registration.state = .notRegistered
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(registration.registerCalls, 1)
        XCTAssertEqual(helper.calls, [true])
    }

    func testNeedsApprovalAfterRegistering() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .requiresApproval
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .needsApproval)
        XCTAssertEqual(registration.openedSettings, 1)
        XCTAssertTrue(helper.calls.isEmpty)
        XCTAssertEqual(controller.tooltip, "Allow Perch in System Settings → Login Items")
    }

    /// `SMAppService.register()` throws when approval is pending; that is the
    /// approval case, not a failure.
    func testRegisterThrowingWhileApprovalPendingIsNeedsApproval() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .requiresApproval
        registration.registerError = SleepHelperError("Operation not permitted")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .needsApproval)
        XCTAssertTrue(helper.calls.isEmpty)
    }

    func testAlreadyAwaitingApprovalDoesNotRegisterAgain() async {
        registration.state = .requiresApproval
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(registration.registerCalls, 0)
        XCTAssertEqual(registration.openedSettings, 1)
        XCTAssertEqual(controller.status, .needsApproval)
    }

    func testRegistrationFailureIsReported() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .notRegistered
        registration.registerError = SleepHelperError("The helper could not be found")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .failed("The helper could not be found"))
        XCTAssertTrue(helper.calls.isEmpty)
        XCTAssertEqual(registration.openedSettings, 0)
    }

    func testRefreshPicksUpAChangeMadeOutsidePerch() {
        let controller = makeController()
        reader.value = true

        controller.refresh()

        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testRefreshClearsNeedsApprovalOnceEnabled() async {
        registration.state = .requiresApproval
        let controller = makeController()
        await controller.toggle()
        XCTAssertEqual(controller.status, .needsApproval)

        registration.state = .enabled
        controller.refresh()

        XCTAssertEqual(controller.status, .ready)
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
