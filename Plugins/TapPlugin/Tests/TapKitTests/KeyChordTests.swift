import Carbon.HIToolbox
import TapKit
import XCTest

final class KeyChordTests: XCTestCase {
    func testPlainShortcut() {
        XCTAssertEqual(KeyChord(parsing: "cmd+shift+3"), KeyChord(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .shift]))
    }

    func testSymbolsAndWords() {
        let expected = KeyChord(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command, .option])
        XCTAssertEqual(KeyChord(parsing: "⌘⌥S"), expected)
        XCTAssertEqual(KeyChord(parsing: "Command-Option-S"), expected)
        XCTAssertEqual(KeyChord(parsing: " alt + cmd + s "), expected)
    }

    func testNamedKeysAndFunction() {
        XCTAssertEqual(KeyChord(parsing: "fn+ctrl+left"), KeyChord(keyCode: UInt16(kVK_LeftArrow), modifiers: [.function, .control]))
        XCTAssertEqual(KeyChord(parsing: "esc"), KeyChord(keyCode: UInt16(kVK_Escape)))
        XCTAssertEqual(KeyChord(parsing: "cmd+space"), KeyChord(keyCode: UInt16(kVK_Space), modifiers: [.command]))
        XCTAssertEqual(KeyChord(parsing: "F11"), KeyChord(keyCode: UInt16(kVK_F11)))
    }

    func testNoKeyOrUnknownKey() {
        XCTAssertNil(KeyChord(parsing: "cmd+shift"))
        XCTAssertNil(KeyChord(parsing: ""))
        XCTAssertNil(KeyChord(parsing: "cmd+banana"))
    }
}
