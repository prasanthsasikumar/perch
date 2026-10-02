import Foundation

/// What a knock does. The raw values are stored in the user's gesture map,
/// so they must never change.
public enum ActionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case copy
    case paste
    case cut
    case undo
    case redo
    case save
    case selectAll
    case aiAccept
    case aiReject
    case newTab
    case closeTab
    case screenshot
    case screenshotSelection
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case mute
    case volumeUp
    case volumeDown
    case lockScreen
    case sleepDisplay
    case missionControl
    case spotlight
    case showDesktop
    case hideFrontApp
    case hideOthers
    case switchDesktopLeft
    case switchDesktopRight
    case tileLeft
    case tileRight
    case notificationCenter
    case startScreensaver
    case toggleDarkMode
    case dictation
    case openApp
    case openURL
    case runShortcut
    case keyboardShortcut
    case shellCommand
    case appleScript
    case soundFX

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "No Action"
        case .copy: "Copy"
        case .paste: "Paste"
        case .cut: "Cut"
        case .undo: "Undo"
        case .redo: "Redo"
        case .save: "Save"
        case .selectAll: "Select All"
        case .aiAccept: "AI Accept"
        case .aiReject: "AI Reject"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .screenshot: "Screenshot"
        case .screenshotSelection: "Screenshot Selection"
        case .mediaPlayPause: "Play / Pause"
        case .mediaNext: "Next Track"
        case .mediaPrevious: "Previous Track"
        case .mute: "Toggle Mute"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .lockScreen: "Lock Screen"
        case .sleepDisplay: "Sleep Display"
        case .missionControl: "Mission Control"
        case .spotlight: "Spotlight"
        case .showDesktop: "Show Desktop"
        case .hideFrontApp: "Hide Front App"
        case .hideOthers: "Hide Others"
        case .switchDesktopLeft: "Desktop ←"
        case .switchDesktopRight: "Desktop →"
        case .tileLeft: "Tile Window Left"
        case .tileRight: "Tile Window Right"
        case .notificationCenter: "Notification Center"
        case .startScreensaver: "Screensaver"
        case .toggleDarkMode: "Toggle Dark Mode"
        case .dictation: "Dictation"
        case .openApp: "Open App"
        case .openURL: "Open URL"
        case .runShortcut: "Run Shortcut"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .shellCommand: "Shell Command"
        case .appleScript: "AppleScript"
        case .soundFX: "Sound FX Only"
        }
    }

    public var icon: String {
        switch self {
        case .none: "circle.dashed"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .cut: "scissors"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .save: "square.and.arrow.down"
        case .selectAll: "selection.pin.in.out"
        case .aiAccept: "checkmark.circle"
        case .aiReject: "xmark.circle"
        case .newTab: "plus.square.on.square"
        case .closeTab: "xmark.square"
        case .screenshot: "camera.viewfinder"
        case .screenshotSelection: "camera.metering.center.weighted"
        case .mediaPlayPause: "playpause"
        case .mediaNext: "forward.fill"
        case .mediaPrevious: "backward.fill"
        case .mute: "speaker.slash"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "moon.zzz.fill"
        case .missionControl: "squares.below.rectangle"
        case .spotlight: "magnifyingglass"
        case .showDesktop: "menubar.dock.rectangle"
        case .hideFrontApp: "eye.slash"
        case .hideOthers: "eye.slash.fill"
        case .switchDesktopLeft: "arrow.left.to.line"
        case .switchDesktopRight: "arrow.right.to.line"
        case .tileLeft: "rectangle.lefthalf.filled"
        case .tileRight: "rectangle.righthalf.filled"
        case .notificationCenter: "bell.badge"
        case .startScreensaver: "sparkles.tv"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .dictation: "mic.fill"
        case .openApp: "app.badge"
        case .openURL: "safari"
        case .runShortcut: "arrow.triangle.branch"
        case .keyboardShortcut: "keyboard"
        case .shellCommand: "terminal"
        case .appleScript: "applescript"
        case .soundFX: "speaker.wave.2.fill"
        }
    }

    /// Whether the action types into the frontmost app, which is then
    /// brought forward first.
    public var needsAccessibility: Bool {
        switch self {
        case .none, .soundFX, .openApp, .openURL, .runShortcut, .shellCommand:
            false
        case .appleScript, .toggleDarkMode, .notificationCenter, .startScreensaver, .sleepDisplay:
            false
        default:
            true
        }
    }

    public var category: ActionCategory {
        switch self {
        case .none, .soundFX:
            .none
        case .copy, .paste, .cut, .undo, .redo, .save, .selectAll, .aiAccept, .aiReject, .newTab, .closeTab:
            .editing
        case .screenshot, .screenshotSelection, .dictation:
            .capture
        case .mediaPlayPause, .mediaNext, .mediaPrevious, .mute, .volumeUp, .volumeDown:
            .media
        case .lockScreen, .sleepDisplay, .missionControl, .spotlight, .showDesktop, .hideFrontApp, .hideOthers,
             .notificationCenter, .startScreensaver, .toggleDarkMode:
            .system
        case .switchDesktopLeft, .switchDesktopRight, .tileLeft, .tileRight:
            .windows
        case .openApp, .openURL, .runShortcut, .keyboardShortcut, .shellCommand, .appleScript:
            .custom
        }
    }

    public var needsParameter: Bool {
        switch self {
        case .shellCommand, .appleScript, .openURL, .keyboardShortcut, .openApp, .runShortcut: true
        default: false
        }
    }

    public var parameterLabel: String {
        switch self {
        case .shellCommand: "Shell command"
        case .appleScript: "AppleScript"
        case .openURL: "URL"
        case .keyboardShortcut: "Shortcut"
        case .openApp: "App name or bundle ID"
        case .runShortcut: "Shortcuts name"
        default: ""
        }
    }

    public var parameterPlaceholder: String {
        switch self {
        case .shellCommand: "screencapture -i ~/Desktop/shot.png"
        case .appleScript: "tell application \"Safari\" to activate"
        case .openURL: "https://example.com"
        case .keyboardShortcut: "cmd+shift+3"
        case .openApp: "Cursor  or  com.todesktop.230313mzl4w4u92"
        case .runShortcut: "Do Not Disturb"
        default: ""
        }
    }
}

public enum ActionCategory: String, CaseIterable, Identifiable, Sendable {
    case none, editing, capture, media, system, windows, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .editing: "Editing"
        case .capture: "Capture"
        case .media: "Media"
        case .system: "System"
        case .windows: "Windows"
        case .custom: "Custom"
        }
    }

    public var types: [ActionType] {
        ActionType.allCases.filter { $0.category == self }
    }
}
