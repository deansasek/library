import Carbon
import SwiftUI

/// Invisible view that records the next key combination, modified click, scroll, pinch, or swipe while it is in a window.
struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (Shortcut) -> Void
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onRecord = onRecord
        view.onCancel = onCancel
    }

    @MainActor
    final class RecorderView: NSView {
        var onRecord: ((Shortcut) -> Void)?
        var onCancel: (() -> Void)?

        private static let names: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]

        private var monitor: Any?

        // An event monitor instead of first-responder focus: the sheet's own controls take focus first.
        override func viewDidMoveToWindow() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .magnify, .swipe]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        isolated deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private var pinchTotal = 0.0

        /// Returns nil when the event is consumed.
        private func handle(_ event: NSEvent) -> NSEvent? {
            let modifiers = carbonModifiers(event.modifierFlags)
            switch event.type {
            case .leftMouseDown:
                // A click elsewhere ends recording and still reaches what was clicked.
                onCancel?()
                return event
            case .keyDown:
                if event.keyCode == 53 && modifiers == 0 {
                    onCancel?()
                    return nil
                }
                // Other plain keys, such as Return, still reach the sheet's buttons.
                guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return event }
                let key = Self.names[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
                guard !key.isEmpty else { return event }
                onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
            case .rightMouseDown, .otherMouseDown:
                // Everything below needs a modifier, so plain clicks, scrolls, and pinches keep working.
                guard modifiers != 0 else { return event }
                onRecord?(Shortcut(modifiers: modifiers, button: event.buttonNumber))
            case .scrollWheel:
                guard modifiers != 0 else { return event }
                // Wait for a clear scroll before recording.
                if let name = Shortcut.scrollName(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                                  inverted: event.isDirectionInvertedFromDevice),
                   abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 2 {
                    onRecord?(Shortcut(modifiers: modifiers, gesture: name))
                }
            case .magnify:
                guard modifiers != 0 else { return event }
                if event.phase == .began { pinchTotal = 0 }
                pinchTotal += Double(event.magnification)
                if abs(pinchTotal) > 0.25 {
                    onRecord?(Shortcut(modifiers: modifiers, gesture: pinchTotal > 0 ? "pinchOut" : "pinchIn"))
                    pinchTotal = 0
                }
            case .swipe:
                guard modifiers != 0 else { return event }
                onRecord?(Shortcut(modifiers: modifiers,
                                   gesture: Shortcut.swipeName(dx: Double(event.deltaX), dy: Double(event.deltaY))))
            default:
                return event
            }
            return nil
        }
    }
}
