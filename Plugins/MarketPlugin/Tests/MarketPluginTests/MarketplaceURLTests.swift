@testable import MarketPlugin
import XCTest

final class MarketplaceURLTests: XCTestCase {
    func testTheCityIsInThePath() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertTrue(url.path.hasPrefix("/marketplace/auckland/search"))
    }

    func testTheQueryIsEncoded() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(
                query: "GoPro Hero 12", maxPrice: nil, location: "auckland", radiusKm: 50
            )
        )

        XCTAssertTrue(url.absoluteString.contains("query=GoPro%20Hero%2012"))
    }

    func testThePriceCapIsIncludedWhenSet() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: 200, location: "auckland", radiusKm: 50)
        )

        XCTAssertTrue(url.absoluteString.contains("maxPrice=200"))
    }

    func testThePriceCapIsOmittedWhenUnset() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertFalse(url.absoluteString.contains("maxPrice"))
    }

    func testTheRadiusIsIncluded() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 20)
        )

        XCTAssertTrue(url.absoluteString.contains("radius=20"))
    }

    func testABlankLocationHasNoURL() {
        XCTAssertNil(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "  ", radiusKm: 50)
        )
    }

    func testItIsAlwaysHTTPSOnFacebook() throws {
        let url = try XCTUnwrap(
            marketplaceSearchURL(query: "GoPro", maxPrice: nil, location: "auckland", radiusKm: 50)
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.facebook.com")
    }
}
