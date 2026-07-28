import PerchKit
import XCTest

final class PluginCapabilityTests: XCTestCase {
    func testEmptySetDisclosesLocalOnly() {
        let capabilities: Set<PluginCapability> = []
        XCTAssertEqual(capabilities.disclosureLines, ["Stays entirely on your Mac"])
    }

    func testEachCapabilityHasItsOwnLine() {
        XCTAssertEqual(Set([PluginCapability.network]).disclosureLines, ["Connects to the internet"])
        XCTAssertEqual(
            Set([PluginCapability.credentials]).disclosureLines,
            ["Stores an account credential"]
        )
        XCTAssertEqual(
            Set([PluginCapability.notifications]).disclosureLines,
            ["Sends notifications"]
        )
    }

    func testMultipleCapabilitiesAreOrderedDeterministically() {
        let capabilities: Set<PluginCapability> = [.notifications, .network, .credentials]
        XCTAssertEqual(
            capabilities.disclosureLines,
            ["Stores an account credential", "Connects to the internet", "Sends notifications"]
        )
    }
}
