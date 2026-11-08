import CoreGraphics
import Foundation
import ScrollKit

/// The event tap that turns scrolls around. It sits on the main run loop, so
/// its callback and everything that sets `settings` share one thread.
///
/// The callback runs for every scroll on the Mac, and macOS disables a tap
/// that is slow to answer, so it reads two phase fields, decides, and at
/// most rewrites six numbers. Nothing in it allocates or logs.
final class ScrollTap {
    var settings = ScrollSettings.default
    private(set) var lastDevice: ScrollDevice?
    private(set) var lastWasReversed = false

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Returns false if macOS refused, which it does without Accessibility.
    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        // Appended at the tail, as Scroll Reverser does, so a scroll is
        // turned around after any other tap (a mouse utility's smoothing,
        // say) has had it, and the app gets the final word.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        lastDevice = nil
        lastWasReversed = false
    }

    /// macOS switches a tap off when a callback is slow, or when secure input
    /// starts; switch it back on.
    func reenable() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func handle(_ event: CGEvent) {
        let device = ScrollClassifier.device(
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )
        let axes = settings.axesToReverse(for: device)
        lastDevice = device
        lastWasReversed = !axes.isEmpty
        ScrollReversal.reverse(axes, on: EventFields(event: event))
    }
}

/// A scroll event's delta fields, the way `ScrollReversal` reads and writes them.
private struct EventFields: ScrollFieldAccess {
    let event: CGEvent

    func value(of field: ScrollField) -> Double {
        field.isFractional
            ? event.getDoubleValueField(field.eventField)
            : Double(event.getIntegerValueField(field.eventField))
    }

    func setValue(_ value: Double, of field: ScrollField) {
        if field.isFractional {
            event.setDoubleValueField(field.eventField, value: value)
        } else {
            event.setIntegerValueField(field.eventField, value: Int64(value))
        }
    }
}

/// Returns the event it was given, changed in place or not.
private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tap.reenable()
    case .scrollWheel:
        tap.handle(event)
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
