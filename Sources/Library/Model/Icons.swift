import SwiftUI

/// Asking the system for an icon is slow, and lists ask on every redraw, so each one is kept. An app that is
/// updated gets a new modification date, which replaces its cached icon. The date is checked on disk at most
/// once every few seconds, so redraws in between do not touch the disk.
func appIcon(at path: String) -> NSImage {
    let modified = modificationDates.modified(at: path, now: DispatchTime.now().uptimeNanoseconds) {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
    return iconCache.icon(at: path, modified: modified) {
        let icon = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

private let iconCache = IconCache()
private let modificationDates = ModificationDateCache()

/// Modification dates by path, read again only after `maxAge`. Times come from the monotonic clock, so a
/// change to the wall clock does not matter. An app updated within the window keeps its old icon until it ends.
final class ModificationDateCache: @unchecked Sendable {
    static let maxAge: UInt64 = 5_000_000_000
    private let lock = NSLock()
    private var stamps: [String: (checked: UInt64, modified: Date?)] = [:]

    /// The cached date when it was read less than `maxAge` before `now` (in nanoseconds), else `read()`.
    func modified(at path: String, now: UInt64, read: () -> Date?) -> Date? {
        lock.lock()
        if let stamp = stamps[path], now &- stamp.checked < Self.maxAge {
            lock.unlock()
            return stamp.modified
        }
        lock.unlock()
        let modified = read()
        lock.lock()
        stamps[path] = (now, modified)
        lock.unlock()
        return modified
    }
}

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
        let glyph = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        let size = glyph.size()
        glyph.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
        return true
    }
}
