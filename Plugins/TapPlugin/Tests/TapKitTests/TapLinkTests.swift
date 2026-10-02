import TapKit
import XCTest

final class TapLinkTests: XCTestCase {
    func testEveryCommandRoundTrips() {
        var commands: [TapCommand] = [.reload, .quit, .start, .stop, .live, .previewHUD, .simulateArrows(true), .simulateArrows(false)]
        for kind in PermissionKind.allCases {
            commands += [.request(kind), .openSystemSettings(kind)]
        }
        for side in TapSide.allCases {
            commands += (1...3).map { .test(side, $0) }
        }
        for command in commands {
            XCTAssertEqual(TapCommand(encoded: command.encoded), command, command.encoded)
        }
    }

    func testMalformedCommandsAreRefused() {
        for text in ["", "reload:now", "request:root", "test:left:4", "test:up:1", "test:left", "simulate:yes", "shell:rm"] {
            XCTAssertNil(TapCommand(encoded: text), text)
        }
    }

    func testStatusRoundTrips() throws {
        var status = TapStatus()
        status.source = .spu
        status.isStreaming = true
        status.sampleRateHz = 801
        status.gestureSequence = 7
        status.lastGesture = DetectedGesture(side: .right, tapCount: 2, timestamp: 3, peakMagnitude: 0.3, peakX: 0.01)
        status.lastExecuted = .paste
        status.permissions.accessibility = .granted
        status.live = LiveFrame(magnitude: [0.1, 0.2], noiseFloor: 0.004, lastRejectReason: "typing")
        let encoded = try XCTUnwrap(status.encoded)
        XCTAssertEqual(TapStatus(encoded: encoded), status)
        XCTAssertNil(TapStatus(encoded: "not json"))
    }

    func testEitherGrantLetsKnocksType() {
        var permissions = TapPermissions()
        XCTAssertFalse(permissions.canPostEvents)
        permissions.postEvent = .granted
        XCTAssertTrue(permissions.canPostEvents)
        XCTAssertEqual(permissions.state(of: .accessibility), .granted)
    }

    func testSimulationCountsAsASensor() {
        var status = TapStatus()
        XCTAssertFalse(status.isSensorAvailable)
        status.arrowSimulation = true
        XCTAssertTrue(status.isSensorAvailable)
    }

    func testThinningKeepsTheSpike() {
        var values = [Double](repeating: 0.001, count: 240)
        values[121] = 0.3
        let thinned = LiveFrame.thin(values, to: 120)
        XCTAssertEqual(thinned.count, 120)
        XCTAssertEqual(thinned.max() ?? 0, 0.3, accuracy: 1e-6)
    }

    func testThinningLeavesShortHistoriesAlone() {
        XCTAssertEqual(LiveFrame.thin([0.1, 0.2], to: 120), [0.1, 0.2])
    }
}
