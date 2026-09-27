@testable import Perch
import XCTest

final class CompanionPlanTests: XCTestCase {
    func testAnUnregisteredHelperIsRegistered() {
        XCTAssertTrue(CompanionPlan.shouldRegister(.notRegistered))
    }

    func testAHelperAwaitingApprovalIsNotRegisteredAgain() {
        XCTAssertFalse(CompanionPlan.shouldRegister(.requiresApproval))
    }

    /// Unregistering to "repair" it was tried: macOS then marks the helper
    /// disabled, which turns a helper that was slow to answer into one that
    /// needs approving all over again.
    func testAnEnabledHelperIsNeverReRegistered() {
        XCTAssertFalse(CompanionPlan.shouldRegister(.enabled))
    }

    func testAHelperAwaitingApprovalOpensLoginItemsQuietly() {
        XCTAssertEqual(CompanionPlan.outcome(for: .requiresApproval), .askForApproval)
    }

    /// Perch only runs the companion when it could not reach the helper, so
    /// an enabled helper here is one that is allowed and not answering.
    /// Leaving without a word would be a dead end.
    func testAnEnabledButUnreachableHelperIsExplained() {
        XCTAssertEqual(CompanionPlan.outcome(for: .enabled), .explainNotResponding)
    }

    /// Where a helper switched off in Login Items lands: registering is
    /// refused, and the status stays "not registered".
    func testARefusedRegistrationIsExplained() {
        XCTAssertEqual(CompanionPlan.outcome(for: .notRegistered), .explainNotAllowed)
    }
}
