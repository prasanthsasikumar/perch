@testable import Perch
import XCTest

final class PmsetCommandTests: XCTestCase {
    func testExecutableIsTheSystemPmset() {
        XCTAssertEqual(PmsetCommand.executable, "/usr/bin/pmset")
    }

    func testArgumentsToDisableSleep() {
        XCTAssertEqual(PmsetCommand.arguments(disabled: true), ["-a", "disablesleep", "1"])
    }

    func testArgumentsToRestoreSleep() {
        XCTAssertEqual(PmsetCommand.arguments(disabled: false), ["-a", "disablesleep", "0"])
    }

    func testFailureMessageUsesStderr() {
        XCTAssertEqual(
            PmsetCommand.failureMessage(status: 1, stderr: "pmset: must be root\n"),
            "pmset: must be root"
        )
    }

    func testFailureMessageFallsBackToExitStatus() {
        XCTAssertEqual(
            PmsetCommand.failureMessage(status: 71, stderr: "  \n"),
            "pmset exited with status 71"
        )
    }

    func testRequirementsNameTheTeamAndEachSide() {
        XCTAssertTrue(SleepHelper.clientRequirement.contains("identifier \"org.ahlab.Perch\""))
        XCTAssertTrue(SleepHelper.helperRequirement.contains("identifier \"org.ahlab.Perch.helper\""))
        for requirement in [SleepHelper.clientRequirement, SleepHelper.helperRequirement] {
            XCTAssertTrue(requirement.contains("anchor apple generic"))
            XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"3U4384584Z\""))
        }
    }
}
