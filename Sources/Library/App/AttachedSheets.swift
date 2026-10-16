import AppKit

/// Attaches file panels and alerts to the window the user is working in, as macOS sheets. When no window of this app
/// is key, the panel or alert runs as an app-modal dialog, as it did before.
@MainActor
enum AttachedSheets {
    /// The window a sheet attaches to: this app's key window, when it is an ordinary visible window. Panels such as
    /// Quick Open are skipped, since a sheet does not belong on them.
    static var host: NSWindow? {
        guard let window = NSApp.keyWindow, window.isVisible, window.styleMask.contains(.titled), !(window is NSPanel) else {
            return nil
        }
        return window
    }

    /// Shows a save or open panel. `completion` gets the chosen file, or nil when the user cancels.
    static func choose(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        guard let window = host else {
            completion(panel.runModal() == .OK ? panel.url : nil)
            return
        }
        panel.beginSheetModal(for: window) { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// Shows an alert. `completion` gets the button the user pressed.
    static func alert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        guard let window = host else {
            NSApp.activate(ignoringOtherApps: true)
            completion(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }
}

extension NSAlert {
    /// Adds the action and Cancel in the macOS order: Cancel on the left, the action on the right. The action is the
    /// first button, so it returns `.alertFirstButtonReturn`. Cancel stays the default button, so Return still cancels.
    @discardableResult
    func addActionWithCancelOnLeft(_ action: String, cancel: String) -> NSButton {
        let button = addButton(withTitle: action)
        let cancelButton = addButton(withTitle: cancel)
        button.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"
        return button
    }
}
