// Draws Resources/AppIcon.icns: a white bookmark symbol on a blue squircle.
// Run: swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    // macOS icon grid: the shape fills 80% of the canvas.
    let body = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.30, green: 0.63, blue: 1.0, alpha: 1),
                        NSColor(red: 0.04, green: 0.35, blue: 0.85, alpha: 1)])!
        .draw(in: shape, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(configuration)!
    symbol.draw(in: NSRect(x: size / 2 - symbol.size.width / 2, y: size / 2 - symbol.size.height / 2,
                           width: symbol.size.width, height: symbol.size.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let files: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in files {
    try png(pixels: pixels).write(to: dir.appendingPathComponent("\(name).png"))
}
