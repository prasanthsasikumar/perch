// Generates every PNG the AppIcon.appiconset's Contents.json references: a
// white bird on a teal rounded rect, rendered fresh at each pixel size rather
// than resampled from one master, so small sizes stay crisp.
//
// Rendering the SF Symbol is also how the `bird` availability requirement
// gets verified: if the symbol is missing on this macOS version, the script
// fails loudly instead of the app silently showing a blank menu bar item.
// Two names are checked, not one: `bird.fill`, which this script draws, and
// plain `bird`, which is what PerchApp.swift falls back to in the menu bar
// when no plugin contributes a label. The icon only proves the first; without
// checking the second too, that fallback could go missing on some future
// macOS version without this script ever noticing.
//
// Run: swift scripts/make_icon.swift
import AppKit

let symbolName = "bird.fill"
let runtimeFallbackSymbolName = "bird"

func requireSymbol(_ name: String) -> NSImage {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        FileHandle.standardError.write(
            Data("error: SF Symbol '\(name)' is unavailable on this macOS version\n".utf8)
        )
        exit(1)
    }
    return symbol
}

let symbol = requireSymbol(symbolName)
// Not used for drawing — this call exists solely to verify the app's runtime
// fallback symbol still exists on this macOS version.
_ = requireSymbol(runtimeFallbackSymbolName)

// The exact pixel sizes Contents.json asks for, by filename.
let sizes: [(filename: String, pixels: CGFloat)] = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024),
]

func renderIcon(pixels: CGFloat) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor(calibratedRed: 0.11, green: 0.51, blue: 0.51, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(origin: .zero, size: size),
        xRadius: pixels * (184.0 / 1024.0),
        yRadius: pixels * (184.0 / 1024.0)
    ).fill()

    let configuration = NSImage.SymbolConfiguration(pointSize: pixels * 0.5469, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    let glyph = symbol.withSymbolConfiguration(configuration) ?? symbol
    let glyphSize = glyph.size
    glyph.draw(
        in: NSRect(
            x: (size.width - glyphSize.width) / 2,
            y: (size.height - glyphSize.height) / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
    )

    image.unlockFocus()
    return image
}

let outputDirectory = URL(fileURLWithPath: "Perch/Resources/Assets.xcassets/AppIcon.appiconset")

for (filename, pixels) in sizes {
    let image = renderIcon(pixels: pixels)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("error: failed to render \(filename)\n".utf8))
        exit(1)
    }
    let destination = outputDirectory.appendingPathComponent(filename)
    try! png.write(to: destination)
    print("Wrote \(destination.path)")
}
