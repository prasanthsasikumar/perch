@testable import Perch
import Security
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

    private func requirement(_ text: String) throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        XCTAssertEqual(status, errSecSuccess, "does not parse: \(text)")
        return try XCTUnwrap(requirement)
    }

    func testRequirementsParse() throws {
        _ = try requirement(SleepHelper.clientRequirement)
        _ = try requirement(SleepHelper.helperRequirement)
    }

    /// The tests run inside Perch, so Perch itself is the client to check.
    func testPerchSatisfiesTheClientRequirement() throws {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        let status = SecCodeCheckValidity(
            try XCTUnwrap(code), [], try requirement(SleepHelper.clientRequirement)
        )
        XCTAssertEqual(status, errSecSuccess)
    }

    func testPerchDoesNotPassForTheHelper() throws {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        let status = SecCodeCheckValidity(
            try XCTUnwrap(code), [], try requirement(SleepHelper.helperRequirement)
        )
        XCTAssertNotEqual(status, errSecSuccess)
    }
}
