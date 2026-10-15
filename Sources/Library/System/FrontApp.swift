import AppKit
import Carbon

/// What Library can learn about, and do in, the app in front. All of it uses Accessibility access, which
/// Library already asks for, and does nothing without it.
enum FrontApp {
    /// The system-wide element. Its messaging timeout is the default for every element it reaches, so a hung app in front
    /// can hold the main thread for only this long, not for the system default of several seconds.
    private static func systemWide() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    /// The control that has the keyboard in the app in front.
    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
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

    /// The key code that types `letter` on the current keyboard layout, found by asking the layout what each key types.
    /// Key 9 is V on QWERTY, and is the fallback when no key types the letter.
    static func keyCode(typing letter: String, character: (CGKeyCode) -> String?) -> CGKeyCode {
        for code in CGKeyCode(0)..<CGKeyCode(128) where character(code)?.lowercased() == letter {
            return code
        }
        return 9
    }

    /// The character a key types on the current keyboard layout, without dead keys or modifiers. Nil when the layout
    /// is not available.
    private static func layoutCharacter(for code: CGKeyCode) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let capacity = characters.count
        let status = layout.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(base, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, capacity, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// Presses Command-V in the app in front, a moment later so a closing menu or panel has handed the keyboard back.
    /// The V key is found on the current layout, so Command-V pastes on Dvorak and other layouts too.
    static func pasteSoon() {
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let pasteKey = keyCode(typing: "v", character: layoutCharacter(for:))
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: pasteKey, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
