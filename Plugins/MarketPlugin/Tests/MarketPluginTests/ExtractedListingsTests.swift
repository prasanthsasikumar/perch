@testable import MarketPlugin
import XCTest

final class ExtractedListingsTests: XCTestCase {
    func testDecodesAListing() throws {
        let json = """
        [{"id":"123","title":"GoPro Hero 12","price":"$180",
          "location":"Auckland","url":"https://www.facebook.com/marketplace/item/123",
          "imageURL":"https://img.example/1.jpg"}]
        """

        let listings = try decodeExtractedListings(json)

        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings[0].id, "123")
        XCTAssertEqual(listings[0].title, "GoPro Hero 12")
        XCTAssertEqual(listings[0].price, "$180")
        XCTAssertEqual(listings[0].priceValue, 180)
        XCTAssertEqual(listings[0].location, "Auckland")
    }

    func testAnEmptyArrayDecodesToNothing() throws {
        XCTAssertTrue(try decodeExtractedListings("[]").isEmpty)
    }

    func testAMissingImageIsAllowed() throws {
        let json = """
        [{"id":"1","title":"T","price":"$1","location":"L",
          "url":"https://www.facebook.com/marketplace/item/1","imageURL":null}]
        """

        XCTAssertNil(try decodeExtractedListings(json)[0].imageURL)
    }

    func testAnEntryWithAnUnusableURLIsSkippedRatherThanFailingTheBatch() throws {
        // One malformed row must not lose the whole poll.
        let json = """
        [{"id":"1","title":"T","price":"$1","location":"L","url":"not a url","imageURL":null},
         {"id":"2","title":"U","price":"$2","location":"L",
          "url":"https://www.facebook.com/marketplace/item/2","imageURL":null}]
        """

        XCTAssertEqual(try decodeExtractedListings(json).map(\.id), ["2"])
    }

    func testGarbageIsAnError() {
        XCTAssertThrowsError(try decodeExtractedListings("not json"))
    }

    func testAFreePriceDecodesWithNoNumericValue() throws {
        let json = """
        [{"id":"1","title":"T","price":"Free","location":"L",
          "url":"https://www.facebook.com/marketplace/item/1","imageURL":null}]
        """

        XCTAssertNil(try decodeExtractedListings(json)[0].priceValue)
    }
}
