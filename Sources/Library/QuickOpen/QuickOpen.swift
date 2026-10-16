import Quartz
import SwiftUI

/// Spotlight-style floating search over everything in the library.
@MainActor
enum QuickOpen {
    private static var panel: QuickOpenPanel?

    /// Opens Quick Open. Used again while it is open, the same shortcut closes it.
    static func show(store: LibraryStore) {
        if let open = panel, open.isOpen {
            open.close()
            return
        }
        // Read before the panel opens, while the app in front still has the keyboard.
        let model = QuickOpenModel(store: store, selectedText: FrontApp.selectedText(),
                                   pastes: ClipboardHistory.shared.shouldPaste)
        let panel = QuickOpenPanel()
        let controller = NSHostingController(rootView: QuickOpenView(model: model) { [weak panel] in panel?.close() })
        controller.sizingOptions = []
        panel.contentViewController = controller
        panel.onMove = { model.move($0) }
        panel.onTab = { model.toggleActions() }
        panel.onSpace = { model.togglePreview() }
        panel.onEscape = { [weak panel] in
            if model.actionGroup != nil {
                model.actionGroup = nil
            } else if model.showActions {
                model.showActions = false
            } else {
                panel?.close()
            }
        }
        panel.onActivate = { [weak panel] in
            let flip = NSEvent.modifierFlags.contains(.option)
            // Choosing a submenu keeps Quick Open open for its items.
            if !model.selectedActionOpensGroup { panel?.close() }
            model.activate(flip: flip)
        }
        panel.onSelectIndex = { [weak panel] index in
            if model.select(index: index) { panel?.onActivate?() }
        }

        // Center the card on the screen under the pointer, as Spotlight is. Its height comes from the rows it will
        // show, so the panel is placed before it appears. It then stays put, so the field does not jump while
        // typing. A row is 42 pt, a header 29 pt, and the list has 16 pt of padding, at least 200 pt so the preview has room, and stops at 340 pt.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let size = NSSize(width: 780, height: 520)
        let padding: CGFloat = 28
        let rows = model.results
        let headers = rows.filter { $0.section != nil }.count
        let listHeight = rows.isEmpty ? 0 : max(200, min(16 + CGFloat(headers) * 29 + CGFloat(rows.count) * 42, 340))
        let cardHeight = 56 + (rows.isEmpty ? 0 : 1 + listHeight)
        if let frame = screen?.frame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY + cardHeight / 2 + padding - size.height,
                                  width: size.width, height: size.height), display: false)
        }
        panel.watchForSpotlight()
        panel.closeAfterDrop(model)
        panel.watchPreviewFocus()
        // No NSApp.activate: it would bring the Library window forward, which takes the key from the panel
        // and closes it. A non-activating panel takes the keyboard without it, as Spotlight does.
        panel.makeKeyAndOrderFront(nil)
        // The card starts small and transparent, then springs in.
        DispatchQueue.main.async { model.appeared = true }
        // Put the cursor in the search field once the panel has the keyboard. SwiftUI's focus state can run
        // before that, so the field is focused through AppKit too.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, let content = panel.contentView else { return }
            panel.makeFirstResponder(textField(in: content))
        }
        self.panel = panel
    }
}

/// Which window has the key, as far as Quick Open's decisions go.
enum QuickOpenKeyHolder {
    case quickOpen, preview, other
}

/// When Quick Open closes as the key window moves. The Quick Look preview is part of Quick Open, so the user can
/// click into it without Quick Open closing; any other window taking the key closes Quick Open.
enum QuickOpenFocus {
    /// - Parameters:
    ///   - newKey: the window that has the key now, or nil when no window of the app has it.
    ///   - previewOpen: whether the Quick Look preview is showing.
    static func closes(whenKeyGoesTo newKey: QuickOpenKeyHolder?, previewOpen: Bool) -> Bool {
        switch newKey {
        case .quickOpen: return false
        case .preview: return !previewOpen
        case .other, nil: return true
        }
    }
}

/// The first text field in a view tree.
@MainActor
private func textField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap(textField(in:)).first
}

/// Borderless panel that takes the keyboard and closes when it loses focus.
private final class QuickOpenPanel: NSPanel {
    var onMove: ((Int) -> Void)?
    var onActivate: (() -> Void)?
    var onSelectIndex: ((Int) -> Void)?
    var onTab: (() -> Void)?
    var onEscape: (() -> Void)?
    /// Returns true when Space was used to preview a clip, so it is not typed.
    var onSpace: (() -> Bool)?

    /// Key codes of the digits 1 to 9 on the number row.
    private static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        // The system shadow follows the card's rounded, translucent shape, because the panel is clear outside it.
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    private var cleanup: [() -> Void] = []

    override func resignKey() {
        super.resignKey()
        // Clicking the preview makes it the key window, which is not a reason to close. The key window is read once
        // it has settled, so the decision sees where the key went.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                // The system's Touch ID or password prompt takes the key, which is not a reason to close.
                guard let self, self.isOpen, !ClipboardLock.shared.isPrompting else { return }
                if QuickOpenFocus.closes(whenKeyGoesTo: self.keyHolder, previewOpen: ClipPreview.shared.isOpen) {
                    self.close()
                }
            }
        }
    }

    /// The window that has the key now, as Quick Open's decisions see it.
    private var keyHolder: QuickOpenKeyHolder? {
        guard let key = NSApp.keyWindow else { return nil }
        if key === self { return .quickOpen }
        if key is QLPreviewPanel { return .preview }
        return .other
    }

    /// Watches the Quick Look preview losing the key. If the preview is still open, Quick Open closes when the key went
    /// to another window. If the preview has closed (Escape, or nothing to show for the selection), Quick Open takes the
    /// keyboard back, so the next Escape closes it.
    func watchPreviewFocus() {
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil,
                                                              queue: .main) { [weak self] note in
            guard note.object is QLPreviewPanel else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.previewResignedKey() }
            }
        }
        cleanup.append { NotificationCenter.default.removeObserver(observer) }
    }

    private func previewResignedKey() {
        guard isOpen else { return }
        if ClipPreview.shared.isOpen {
            if QuickOpenFocus.closes(whenKeyGoesTo: keyHolder, previewOpen: true) { close() }
        } else {
            makeKeyAndOrderFront(nil)
        }
    }

    private var isClosing = false

    /// Showing and not on its way out.
    var isOpen: Bool { isVisible && !isClosing }

    /// Fades out quickly instead of vanishing.
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        cleanup.forEach { $0() }
        cleanup = []
        ClipPreview.shared.close()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || alphaValue == 0 {
            super.close()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.06
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // The completion runs on the main thread, which the panel's main-actor methods need.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        })
    }

    /// Closes the panel when a dragged row is dropped, anywhere. Releasing the button ends every drag.
    func closeAfterDrop(_ model: QuickOpenModel) {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            guard model.isDragging else { return }
            model.isDragging = false
            // A moment later, so the drop finishes before the panel goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.close() }
        }
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: handler)
        cleanup.append { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    /// Closes the panel when another app comes to the front or Spotlight appears. A non-activating panel
    /// keeps the key when Spotlight opens, so the key change alone does not close it.
    func watchForSpotlight() {
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                          queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // The authentication prompt comes from another process, so it must not close Quick Open.
            if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                MainActor.assumeIsolated {
                    guard !ClipboardLock.shared.isPrompting else { return }
                    self?.close()
                }
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            // Spotlight also owns its small menu bar item, so only a large window counts as its search.
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let isSearchOpen = windows.contains { window in
                guard window[kCGWindowOwnerName as String] as? String == "Spotlight",
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
                return (bounds["Height"] ?? 0) > 80 && (bounds["Width"] ?? 0) > 300
            }
            if isSearchOpen {
                MainActor.assumeIsolated { self?.close() }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        cleanup += [{ center.removeObserver(observer) }, { timer.invalidate() }]
    }

    // Arrows, Return, Tab, Escape, and Command-1 to Command-9 go to the list before the text field sees them.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.modifierFlags.contains(.command), let index = Self.digitKeys.firstIndex(of: event.keyCode) {
                onSelectIndex?(index)
                return
            }
            switch event.keyCode {
            case 125: onMove?(1); return
            case 126: onMove?(-1); return
            case 36, 76: onActivate?(); return
            case 48: onTab?(); return
            case 53: onEscape?(); return
            case 49 where event.modifierFlags.intersection([.command, .option, .control]).isEmpty:
                if onSpace?() == true { return }
            default: break
            }
            returnTypingToSearchField()
        }
        super.sendEvent(event)
    }

    /// A click or right-click on a List row can make the list the first responder. Its type-to-select would then take
    /// the letters typed next, so the search field gets the keyboard back before a key is delivered.
    private func returnTypingToSearchField() {
        guard let content = contentView, !(firstResponder is NSText) else { return }
        if let field = textField(in: content) { makeFirstResponder(field) }
    }
}
