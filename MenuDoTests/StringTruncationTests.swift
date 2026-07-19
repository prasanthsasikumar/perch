import XCTest
@testable import MenuDo

final class StringTruncationTests: XCTestCase {
    func testShortStringUnchanged() {
        XCTAssertEqual("Buy milk".truncatedForMenuBar(to: 30), "Buy milk")
    }

    func testExactLengthUnchanged() {
        XCTAssertEqual("abcde".truncatedForMenuBar(to: 5), "abcde")
    }

    func testLongStringTruncatedWithEllipsis() {
        XCTAssertEqual("abcdefghij".truncatedForMenuBar(to: 5), "abcde…")
    }

    func testTrailingSpaceRemovedBeforeEllipsis() {
        XCTAssertEqual("abcd efghij".truncatedForMenuBar(to: 5), "abcd…")
    }

    func testSurroundingWhitespaceTrimmed() {
        XCTAssertEqual("  hi  ".truncatedForMenuBar(to: 30), "hi")
    }
}
