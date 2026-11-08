import AppKit

/// Perch Scroll: reverses the mouse wheel, the trackpad, or both.
///
/// Perch's Scroll plugin starts this companion from inside Perch.app and
/// shows everything it does; it has no interface of its own. It is not
/// sandboxed — see `ScrollLink` for why, and for what Perch and it exchange.
/// It quits when Perch does.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let companion = Companion(arguments: CommandLine.arguments)
companion.run()
app.run()
