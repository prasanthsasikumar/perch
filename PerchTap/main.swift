import AppKit

/// Perch Tap: knock the MacBook, run a shortcut.
///
/// Perch's Tap plugin starts this companion from inside Perch.app and shows
/// everything it does; it has no interface of its own beyond the knock
/// overlay. It is not sandboxed — see `TapLink` for why, and for what Perch
/// and it exchange. It quits when Perch does.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let companion = Companion(arguments: CommandLine.arguments)
companion.run()
app.run()
