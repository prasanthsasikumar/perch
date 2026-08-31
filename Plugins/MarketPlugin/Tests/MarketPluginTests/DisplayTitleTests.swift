@testable import MarketPlugin
import XCTest

@MainActor
final class DisplayTitleTests: XCTestCase {
    private func listing(title: String, location: String) -> Listing {
        Listing(
            id: "1",
            watchID: UUID(),
            title: title,
            price: "₹1",
            location: location,
            url: URL(string: "https://www.facebook.com/marketplace/item/1")!,
            imageURL: nil
        )
    }

    func testATitleIsShownAsIs() {
        XCTAssertEqual(WatchRowView.displayTitle(listing(title: "Interceptor 650", location: "Kochi, KL")), "Interceptor 650")
    }

    func testAnUntitledListingNamesItsLocationAsAStandIn() {
        XCTAssertEqual(
            WatchRowView.displayTitle(listing(title: "", location: "Palakkad, KL")),
            "Untitled listing in Palakkad, KL"
        )
    }

    func testAnUntitledUnlocatedListingIsStillNamed() {
        XCTAssertEqual(WatchRowView.displayTitle(listing(title: "", location: "")), "Untitled listing")
    }
}
