import AppKit

/// A window that stays exactly where it is put, even off every screen.
///
/// A `WKWebView` outside a window may not lay out or run scripts, so a
/// plugin that scrapes pages keeps its webview in a window parked far
/// off-screen. `NSWindow` defeats that twice over: a titled window's
/// initializer moves a frame that lies off every screen back onto one, and
/// ordering it in runs it through `constrainFrameRect(_:to:)` for the same
/// correction — which is how a 1280×900 "hidden" browser ends up in the
/// middle of the user's display at launch. This subclass re-applies the
/// frame it was asked for after `init`, and declines the correction after
/// that. A plugin that wants the window seen (a sign-in flow) still gets to
/// `center()` it and bring it forward; nothing here stops a deliberate
/// placement.
///
/// A parked window is also kept out of Mission Control and the window
/// cycle. Mission Control lays every normal window out by where it really
/// is, so one 10,000 points away makes it zoom out until the user's own
/// windows shrink to nothing. A plugin that shows the window for real
/// sets `collectionBehavior` to `.managed` while it is up, and back to
/// `ParkedWindow.parkedBehavior` when it parks it again.
public final class ParkedWindow: NSWindow {
    public static let parkedBehavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle]

    override public init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setFrame(frameRect(forContentRect: contentRect), display: false)
        collectionBehavior = Self.parkedBehavior
    }

    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
