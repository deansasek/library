import SwiftUI

/// Asking the system for an icon is slow, and lists ask on every redraw, so each one is kept.
private var appIcons: [String: NSImage] = [:]

func appIcon(at path: String) -> NSImage {
    if let cached = appIcons[path] { return cached }
    let icon = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage) ?? NSImage()
    icon.size = NSSize(width: 16, height: 16)
    appIcons[path] = icon
    return icon
}

/// The 16 pt image for a custom icon: an SF Symbol name or a single emoji. Nil when `text` is neither.
func customIcon(_ text: String) -> NSImage? {
    let text = text.trimmingCharacters(in: .whitespaces)
    if let symbol = NSImage(systemSymbolName: text, accessibilityDescription: nil) {
        return symbol
    }
    // Scalars above U+238C skip ASCII digits and symbols, which also count as emoji.
    guard text.count == 1, text.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x238C })
    else { return nil }
    return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
        let glyph = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let size = glyph.size()
        glyph.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
        return true
    }
}
