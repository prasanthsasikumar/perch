@testable import ServerPlugin
import XCTest

final class ServerSettingsTests: XCTestCase {
    func testTheIntervalIsFlooredNoMatterWhatIsStored() {
        XCTAssertEqual(ServerSettings(refreshIntervalSeconds: 1).refreshInterval, 15)
        XCTAssertEqual(ServerSettings(refreshIntervalSeconds: -30).refreshInterval, 15)
    }

    func testAReasonableIntervalIsLeftAlone() {
        XCTAssertEqual(ServerSettings(refreshIntervalSeconds: 120).refreshInterval, 120)
    }
}
