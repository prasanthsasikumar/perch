@testable import ServerPlugin
import XCTest

/// These strings are user-facing captions, not log lines. They are asserted so
/// that a future refactor cannot quietly leak a URLError description into the
/// panel.
final class ServerErrorTests: XCTestCase {
    func testEachFailureReadsAsASentence() {
        XCTAssertEqual(ServerError.unauthorized.message, "Wrong username or password.")
        XCTAssertEqual(ServerError.unreachable("box.example.com").message, "Couldn't reach box.example.com.")
        XCTAssertEqual(ServerError.badStatus(502).message, "The server replied 502.")
        XCTAssertEqual(ServerError.notAnAgent.message, "That address answered, but not with vpsstat data.")
        XCTAssertEqual(ServerError.badURL.message, "That doesn't look like a web address.")
    }
}
