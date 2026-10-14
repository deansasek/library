import Carbon
import SwiftUI

/// A global trigger: a key combination, or with `button` a modified click, or with `gesture` a
/// scroll, pinch, swipe, or hot corner. `modifiers` holds Carbon flags (`cmdKey`, `optionKey`, ...).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32 = 0
    var modifiers: UInt32
    var key = ""
    /// Mouse button number: 1 is the right button, 2 and up are the other buttons.
    var button: Int?
    /// One of `gestureNames`.
    var gesture: String?
    /// Open in a new window or instance instead of reusing the existing one.
    var openNew = false

    static let gestureNames = [
        "scrollUp": "Scroll Up", "scrollDown": "Scroll Down", "scrollLeft": "Scroll Left", "scrollRight": "Scroll Right",
        "pinchIn": "Pinch In", "pinchOut": "Pinch Out",
        "swipeLeft": "Swipe Left", "swipeRight": "Swipe Right", "swipeUp": "Swipe Up", "swipeDown": "Swipe Down",
        "cornerTopLeft": "Top Left Corner", "cornerTopRight": "Top Right Corner",
        "cornerBottomLeft": "Bottom Left Corner", "cornerBottomRight": "Bottom Right Corner",
    ]
    static let corners = ["cornerTopLeft", "cornerTopRight", "cornerBottomLeft", "cornerBottomRight"]

    /// A placeholder row that has not recorded anything yet.
    var isEmpty: Bool { key.isEmpty && button == nil && gesture == nil }

    var isCorner: Bool { gesture.map(Self.corners.contains) ?? false }

    /// Scroll direction as finger or wheel movement. `inverted` is the natural scrolling setting.
    static func scrollName(dx: Double, dy: Double, inverted: Bool) -> String? {
        if abs(dy) >= abs(dx) {
            return dy == 0 ? nil : ((dy > 0) != inverted ? "scrollUp" : "scrollDown")
        }
        return (dx > 0) == inverted ? "scrollRight" : "scrollLeft"
    }

    static func swipeName(dx: Double, dy: Double) -> String {
        abs(dx) >= abs(dy) ? (dx > 0 ? "swipeLeft" : "swipeRight") : (dy > 0 ? "swipeUp" : "swipeDown")
    }

    private func has(_ flag: Int) -> Bool { modifiers & UInt32(flag) != 0 }

    var description: String {
        let name = button.map { $0 == 1 ? "Right Click" : $0 == 2 ? "Middle Click" : "Button \($0 + 1)" }
            ?? gesture.flatMap { Self.gestureNames[$0] } ?? key
        return (has(controlKey) ? "⌃" : "") + (has(optionKey) ? "⌥" : "")
            + (has(shiftKey) ? "⇧" : "") + (has(cmdKey) ? "⌘" : "") + name
    }

    /// The same combination as a menu key equivalent, so the menu shows it. Single-character keys only.
    var menuShortcut: KeyboardShortcut? {
        guard button == nil, gesture == nil, key.count == 1, let char = key.lowercased().first else { return nil }
        var flags: SwiftUI.EventModifiers = []
        if has(controlKey) { flags.insert(.control) }
        if has(optionKey) { flags.insert(.option) }
        if has(shiftKey) { flags.insert(.shift) }
        if has(cmdKey) { flags.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: flags)
    }

    /// The modifiers as CGEvent flags, for matching clicks, scrolls, and gestures.
    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if has(controlKey) { flags.insert(.maskControl) }
        if has(optionKey) { flags.insert(.maskAlternate) }
        if has(shiftKey) { flags.insert(.maskShift) }
        if has(cmdKey) { flags.insert(.maskCommand) }
        return flags
    }
}

/// Carbon modifier flags for an event's modifier keys.
func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    return modifiers
}
