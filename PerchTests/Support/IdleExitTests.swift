@testable import Perch
import XCTest

@MainActor
final class IdleExitTests: XCTestCase {
    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testFiresAfterAQuietSpell() async {
        var fired = 0
        let idle = IdleExit(delay: 0.05) { fired += 1 }

        idle.touch()
        await pause(0.2)

        XCTAssertEqual(fired, 1)
    }

    func testDoesNotFireWhileARequestIsInFlight() async {
        var fired = 0
        let idle = IdleExit(delay: 0.05) { fired += 1 }
        idle.touch()

        idle.begin()
        await pause(0.2)

        XCTAssertEqual(fired, 0)
    }

    func testFiresOnceTheLastRequestEnds() async {
        var fired = 0
        let idle = IdleExit(delay: 0.05) { fired += 1 }

        idle.begin()
        idle.begin()
        idle.end()
        await pause(0.2)
        XCTAssertEqual(fired, 0)

        idle.end()
        await pause(0.2)
        XCTAssertEqual(fired, 1)
    }

    func testATouchRestartsTheClock() async {
        var fired = 0
        let idle = IdleExit(delay: 0.2) { fired += 1 }

        idle.touch()
        await pause(0.12)
        idle.touch()
        await pause(0.12)

        XCTAssertEqual(fired, 0)
    }
}
