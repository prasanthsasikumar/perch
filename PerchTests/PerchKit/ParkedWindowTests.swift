import AppKit
import PerchKit
import XCTest

@MainActor
final class ParkedWindowTests: XCTestCase {
    private let offscreen = NSRect(x: -10_000, y: -10_000, width: 1280, height: 900)

    private func makeWindow<W: NSWindow>(_ type: W.Type) -> W {
        W(contentRect: offscreen, styleMask: [.titled], backing: .buffered, defer: false)
    }

    /// The premise: a plain titled window does get dragged onto a screen
    /// when ordered in. If this ever stops failing, `ParkedWindow` has
    /// become unnecessary rather than wrong.
    func testAPlainWindowIsClampedOntoAScreen() {
        let window = makeWindow(NSWindow.self)
        defer { window.orderOut(nil) }

        window.orderBack(nil)

        XCTAssertNotEqual(window.frame.origin.x, offscreen.origin.x)
    }

    func testAParkedWindowStaysWhereItWasPut() {
        let window = makeWindow(ParkedWindow.self)
        defer { window.orderOut(nil) }

        window.orderBack(nil)

        XCTAssertEqual(window.frame.origin.x, offscreen.origin.x)
        XCTAssertEqual(window.frame.origin.y, offscreen.origin.y)
    }

    /// Bringing it on screen on purpose still works — the sign-in flow
    /// depends on it.
    func testAParkedWindowCanStillBeCentered() throws {
        let window = makeWindow(ParkedWindow.self)
        defer { window.orderOut(nil) }
        let screen = try XCTUnwrap(NSScreen.main)

        window.center()

        XCTAssertTrue(screen.frame.intersects(window.frame))
    }
}
