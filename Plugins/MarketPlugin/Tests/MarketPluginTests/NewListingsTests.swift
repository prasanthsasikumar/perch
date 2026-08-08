import Foundation
@testable import MarketPlugin
import XCTest

func scraped(_ id: String, title: String = "Item") -> ScrapedListing {
    ScrapedListing(
        id: id,
        title: title,
        price: "$100",
        location: "Auckland",
        url: URL(string: "https://facebook.com/marketplace/item/\(id)")!,
        imageURL: nil
    )
}

final class NewListingsTests: XCTestCase {
    func testEverythingIsNewWhenNothingHasBeenSeen() {
        let found = newListings([scraped("a"), scraped("b")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["a", "b"])
    }

    func testAlreadySeenListingsAreExcluded() {
        let found = newListings([scraped("a"), scraped("b")], seenIDs: ["a"])

        XCTAssertEqual(found.map(\.id), ["b"])
    }

    func testDuplicatesWithinOneFetchAreCollapsed() {
        // Facebook repeats listings as you scroll; reporting twice is a bug.
        let found = newListings([scraped("a"), scraped("a")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["a"])
    }

    func testTheFirstOfADuplicatePairIsKept() {
        let found = newListings(
            [scraped("a", title: "first"), scraped("a", title: "second")], seenIDs: []
        )

        XCTAssertEqual(found.first?.title, "first")
    }

    func testFetchOrderIsPreserved() {
        let found = newListings([scraped("c"), scraped("a"), scraped("b")], seenIDs: [])

        XCTAssertEqual(found.map(\.id), ["c", "a", "b"])
    }

    func testNothingNewYieldsAnEmptyResult() {
        XCTAssertTrue(newListings([scraped("a")], seenIDs: ["a"]).isEmpty)
    }

    func testAnEmptyFetchYieldsAnEmptyResult() {
        XCTAssertTrue(newListings([], seenIDs: ["a"]).isEmpty)
    }
}
