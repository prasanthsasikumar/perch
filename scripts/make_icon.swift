// Generates AppIcon.png (1024×1024): white checkmark on a blue rounded rect.
// Run: swift scripts/make_icon.swift
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.95, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(origin: .zero, size: size),
    xRadius: 184,
    yRadius: 184
).fill()
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 620, weight: .bold),
    .foregroundColor: NSColor.white,
]
let mark = NSAttributedString(string: "✓", attributes: attributes)
let bounds = mark.size()
mark.draw(at: NSPoint(x: (1024 - bounds.width) / 2, y: (1024 - bounds.height) / 2))
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "AppIcon.png"))
print("Wrote AppIcon.png")
