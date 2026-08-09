@testable import MarketPlugin
import XCTest

final class LoginSignalsTests: XCTestCase {
    private func signals(
        path: String = "/marketplace/auckland/search",
        password: Bool = false,
        form: Bool = false,
        listings: Int = 0
    ) -> LoginSignals {
        LoginSignals(
            urlPath: path,
            hasPasswordField: password,
            hasLoginForm: form,
            listingCount: listings
        )
    }

    func testARedirectToLoginIsAWall() {
        XCTAssertTrue(isLoginWall(signals(path: "/login/device-based/regular/login/")))
    }

    func testALoginPathAnywhereIsAWall() {
        XCTAssertTrue(isLoginWall(signals(path: "/login.php")))
    }

    func testAPasswordFieldIsAWall() {
        XCTAssertTrue(isLoginWall(signals(password: true)))
    }

    func testALoginFormIsAWall() {
        XCTAssertTrue(isLoginWall(signals(form: true)))
    }

    func testAnEmptyResultsPageIsNotAWall() {
        // The whole point: "nothing matched" must never be read as "logged
        // out". Conflating them is what made the sign-in prompt unreachable
        // in the superseded Python implementation.
        XCTAssertFalse(isLoginWall(signals(listings: 0)))
    }

    func testAPageWithListingsIsNotAWall() {
        XCTAssertFalse(isLoginWall(signals(listings: 12)))
    }

    func testListingsWinOverAStrayPasswordField() {
        // Facebook renders a hidden login form on some logged-in pages. If we
        // got listings, we are demonstrably logged in.
        XCTAssertFalse(isLoginWall(signals(password: true, listings: 12)))
    }

    func testAMarketplacePathWithNoSignalsIsNotAWall() {
        XCTAssertFalse(isLoginWall(signals()))
    }
}
