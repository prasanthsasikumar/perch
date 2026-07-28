import PerchKit
@testable import Perch
import XCTest

final class MenuBarLabelResolverTests: XCTestCase {
    func testNoContributedLabelResolvesToNil() {
        XCTAssertNil(
            MenuBarLabelResolver.resolve(primary: nil, showTitle: true, truncationLength: 30)
        )
    }

    func testTitleIsDroppedWhenTheUserAsksForIconOnly() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "Buy milk"),
            showTitle: false,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.systemImage, "checkmark.circle")
        XCTAssertNil(resolved?.text)
    }

    func testShortTitlePassesThrough() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "Buy milk"),
            showTitle: true,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.text, "Buy milk")
    }

    func testLongTitleIsTruncated() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "abcdefghij"),
            showTitle: true,
            truncationLength: 5
        )
        XCTAssertEqual(resolved?.text, "abcde…")
    }

    func testAPluginWithNoTextKeepsItsIcon() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: nil),
            showTitle: true,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.systemImage, "checkmark.circle")
        XCTAssertNil(resolved?.text)
    }
}
