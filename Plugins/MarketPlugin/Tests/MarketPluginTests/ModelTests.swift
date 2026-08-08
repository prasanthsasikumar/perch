import Foundation
@testable import MarketPlugin
import XCTest

final class ModelTests: XCTestCase {
    func testANewWatchIsDueImmediately() {
        let watch = Watch(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)

        XCTAssertEqual(watch.nextCheckAt, .distantPast)
        XCTAssertNil(watch.lastCheckedAt)
        XCTAssertEqual(watch.consecutiveFailures, 0)
        XCTAssertFalse(watch.paused)
    }

    func testAWatchRoundTripsThroughJSON() throws {
        let watch = Watch(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)

        let data = try JSONEncoder().encode(watch)
        let decoded = try JSONDecoder().decode(Watch.self, from: data)

        XCTAssertEqual(decoded, watch)
    }

    func testAWatchWithNoPriceCapRoundTrips() throws {
        let watch = Watch(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)

        let decoded = try JSONDecoder().decode(
            Watch.self, from: try JSONEncoder().encode(watch)
        )

        XCTAssertNil(decoded.maxPrice)
    }

    func testANewListingIsUnseen() {
        let listing = Listing(
            id: "123",
            watchID: UUID(),
            title: "GoPro Hero 12",
            price: "$180",
            location: "Auckland",
            url: URL(string: "https://facebook.com/marketplace/item/123")!,
            imageURL: nil
        )

        XCTAssertFalse(listing.seen)
    }

    func testAListingRoundTripsThroughJSON() throws {
        let listing = Listing(
            id: "123",
            watchID: UUID(),
            title: "GoPro Hero 12",
            price: "$180",
            location: "Auckland",
            url: URL(string: "https://facebook.com/marketplace/item/123")!,
            imageURL: URL(string: "https://img.example/1.jpg")
        )

        let decoded = try JSONDecoder().decode(
            Listing.self, from: try JSONEncoder().encode(listing)
        )

        XCTAssertEqual(decoded, listing)
    }

    func testSettingsDefaultToNoLocation() {
        let settings = MarketSettings.defaults

        XCTAssertNil(settings.location)
        XCTAssertEqual(settings.radiusKm, 50)
        XCTAssertEqual(settings.pollIntervalMinutes, 15)
        XCTAssertTrue(settings.notificationsEnabled)
    }
}
