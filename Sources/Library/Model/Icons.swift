import SwiftUI

/// Asking the system for an icon is slow, and lists ask on every redraw, so each one is kept. An app that is
/// updated gets a new modification date, which replaces its cached icon.
func appIcon(at path: String) -> NSImage {
    let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    return iconCache.icon(at: path, modified: modified) {
        let icon = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

private let iconCache = IconCache()

/// Icons by path. A lock lets lists on any thread read it.
private final class IconCache: @unchecked Sendable {
    private let lock = NSLock()
    private var icons: [String: (modified: Date?, icon: NSImage)] = [:]

    func icon(at path: String, modified: Date?, make: () -> NSImage) -> NSImage {
        lock.lock()
        if let cached = icons[path], cached.modified == modified {
            lock.unlock()
            return cached.icon
        }
        lock.unlock()
        let icon = make()
        lock.lock()
        icons[path] = (modified, icon)
        lock.unlock()
        return icon
    }
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
