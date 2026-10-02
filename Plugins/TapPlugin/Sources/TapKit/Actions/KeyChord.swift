import Carbon.HIToolbox
import Foundation

/// A key and the modifiers held with it.
public struct KeyChord: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let option = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Reads what people type: `cmd+shift+3`, `⌘⇧3`, `Command-S`,
    /// `ctrl + left`. `nil` when there is no key, or one it does not know.
    public init?(parsing shortcut: String) {
        var text = shortcut.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("command", "cmd"), ("control", "ctrl"), ("option", "opt"),
            ("alternate", "opt"), ("alt", "opt"),
            ("⌘", "cmd+"), ("⇧", "shift+"), ("⌃", "ctrl+"), ("⌥", "opt+"),
            (" ", ""), ("-", "+"),
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        while text.contains("++") {
            text = text.replacingOccurrences(of: "++", with: "+")
        }
        if text.hasPrefix("+") { text.removeFirst() }
        if text.hasSuffix("+") { text.removeLast() }

        var modifiers: Modifiers = []
        var keyToken: String?
        for part in text.split(separator: "+").map(String.init) where !part.isEmpty {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "ctrl": modifiers.insert(.control)
            case "opt": modifiers.insert(.option)
            case "fn", "globe": modifiers.insert(.function)
            default: keyToken = part
            }
        }
        guard let token = keyToken, let keyCode = Self.keyCode(for: token) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    private static let characters: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "=": kVK_ANSI_Equal,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        "\\": kVK_ANSI_Backslash, ";": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash,
    ]

    private static let named: [String: Int] = [
        "space": kVK_Space,
        "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab,
        "esc": kVK_Escape, "escape": kVK_Escape,
        "delete": kVK_Delete, "backspace": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "plus": kVK_ANSI_Equal, "minus": kVK_ANSI_Minus,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    static func keyCode(for token: String) -> UInt16? {
        if token.count == 1, let character = token.first, let code = characters[character] {
            return UInt16(code)
        }
        return named[token].map(UInt16.init)
    }
}
