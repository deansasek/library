import AppKit

/// What Library can learn about, and do in, the app in front. All of it uses Accessibility access, which
/// Library already asks for, and does nothing without it.
enum FrontApp {
    /// The control that has the keyboard in the app in front.
    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type above. A forced cast would crash if an app ever returned another type.
        return (focused as! AXUIElement)
    }

    /// The selected text, or nil when nothing is selected or the app does not share it. It is used at once to
    /// look for a link and is not kept.
    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        // A link is short. Skipping long selections keeps this cheap.
        return text.count > 2000 ? nil : text
    }

    /// True when the control that has the keyboard takes typed text: a text field, a text area, a combo box, or
    /// anything whose insertion point can be set, as in a web page's input.
    static func isTextInputFocused() -> Bool {
        guard let element = focusedElement() else { return false }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String, ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) {
            return true
        }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// Presses Command-V in the app in front, a moment later so a closing menu or panel has handed the keyboard back.
    static func pasteSoon() {
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
