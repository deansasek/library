import SwiftUI

/// The bookmarks as a native pop-up menu, and a way to open the menu bar icon's own menu.
@MainActor
enum PopupMenu {
    /// Opens the menu bar icon's menu. Returns false when the icon cannot be found.
    static func clickStatusItem() -> Bool {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBarWindow") {
            if let button = window.contentView.flatMap(statusButton) {
                button.performClick(nil)
                return true
            }
        }
        return false
    }

    private static func statusButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, String(describing: type(of: button)).contains("StatusBarButton") {
            return button
        }
        return view.subviews.lazy.compactMap(statusButton).first
    }

    /// Shows the menu at the mouse pointer, like a context menu.
    static func show(store: LibraryStore, selection: String? = nil) {
        let target = Target(store: store)
        let menu = NSMenu()
        let frequent = store.frequent
        if !frequent.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Frequently Used"))
            frequent.forEach { menu.addItem(item(for: $0, target: target)) }
        }
        let reading = store.readingList
        if !reading.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: String(localized: "Reading List", bundle: L10n.bundle)))
            reading.forEach { menu.addItem(item(for: $0, target: target)) }
        }
        fill(menu, with: store.nodes, target: target)
        if let suggestion = store.suggestion(selection: selection) {
            menu.addItem(.separator())
            menu.addItem(suggestionItem(suggestion, action: #selector(Target.addSuggested(_:)), target: target))
        }
        NSApp.activate(ignoringOtherApps: true)
        // Menu items hold their target weakly, so the target must live until the menu closes.
        withExtendedLifetime(target) {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// Shows the clipboard history at the mouse pointer. Choosing an item copies it back.
    static func showClipboard(selection: String? = nil, pastes: Bool = false) {
        // The app that has the keyboard is noted before the menu opens. Library is not activated, so a paste goes
        // back to that app and never lands in Library.
        let previous = NSWorkspace.shared.frontmostApplication
        let (menu, target) = makeClipboardMenu(history: .shared, suggestion: LibraryStore.shared.suggestion(selection: selection),
                                               pastes: pastes, returningTo: previous)
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// The clipboard history as a menu. The first nine items answer to the keys 1 to 9, and Option with the key
    /// picks Copy as Plain Text. The target receives the choices and must stay alive while the menu is open.
    /// When `pastes` is set, choosing an item re-activates `returningTo` before it pastes.
    static func makeClipboardMenu(history: ClipboardHistory, suggestion: AddSuggestion?,
                                  pastes: Bool, returningTo previous: NSRunningApplication? = nil) -> (menu: NSMenu, target: NSObject) {
        let target = ClipTarget(pastes: pastes, returningTo: previous)
        let menu = NSMenu()
        let items = history.displayOrder
        var number = 0
        if let suggestion {
            menu.addItem(suggestionItem(suggestion, action: #selector(ClipTarget.addSuggested(_:)), target: target))
            menu.addItem(.separator())
        }
        if items.isEmpty {
            let empty = NSMenuItem(title: "No Clipboard History", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        // The headers say what choosing an item does: paste into the text field, or copy.
        let verb = pastes ? "Paste " : ""
        for (title, group) in [("\(verb)Pinned", items.filter(\.pinned)), ("\(verb)Recent", Array(items.filter { !$0.pinned }.prefix(20)))]
        where !group.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: title))
            for clip in group {
                number += 1
                // A key with no modifier, so pressing the digit while the menu is open chooses the item.
                let key = number <= 9 ? "\(number)" : ""
                let lock = ClipboardLock.shared
                let item = NSMenuItem(title: lock.menuTitle(for: clip), action: #selector(ClipTarget.copy(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = []
                item.target = target
                item.representedObject = clip.id
                item.image = lock.icon(for: clip)
                item.toolTip = clip.subtitle
                menu.addItem(item)
                // Holding Option swaps the item for Copy as Plain Text, as Mac menus do for such pairs.
                if clip.hasRichFormats {
                    menu.addItem(alternate("Copy as Plain Text", #selector(ClipTarget.copyPlain(_:)), clip, target, key: key))
                }
            }
        }
        if !items.isEmpty {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(ClipTarget.clear(_:)), keyEquivalent: "")
            clear.target = target
            menu.addItem(clear)
        }
        // The queue is listed in order, with the items shown but not chosen. Paste Next copies the first one.
        if !history.pasteQueue.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: String(localized: "Paste Queue (\(history.pasteQueue.count))", bundle: L10n.bundle)))
            for clip in history.pasteQueue {
                // A locked pinned item shows its lock and Pinned Item, as the other rows do.
                let queued = NSMenuItem(title: ClipboardLock.shared.menuTitle(for: clip), action: nil, keyEquivalent: "")
                queued.image = ClipboardLock.shared.icon(for: clip)
                queued.isEnabled = false
                menu.addItem(queued)
            }
            let next = NSMenuItem(title: String(localized: "Paste Next", bundle: L10n.bundle), action: #selector(ClipTarget.pasteNext(_:)), keyEquivalent: "")
            next.target = target
            next.image = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil)
            menu.addItem(next)
            let clearQueue = NSMenuItem(title: String(localized: "Clear Queue", bundle: L10n.bundle), action: #selector(ClipTarget.clearPasteQueue(_:)), keyEquivalent: "")
            clearQueue.target = target
            menu.addItem(clearQueue)
        }
        return (menu, target)
    }

    /// The menu item that adds a suggestion. It carries the suggestion itself.
    private static func suggestionItem(_ suggestion: AddSuggestion, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: suggestion.title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = suggestion
        item.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        item.toolTip = suggestion.subtitle
        return item
    }

    private static func alternate(_ title: String, _ action: Selector, _ clip: ClipItem, _ target: ClipTarget,
                                  key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.representedObject = clip.id
        item.isAlternate = true
        item.keyEquivalentModifierMask = [.option]
        return item
    }

    private static func fill(_ menu: NSMenu, with nodes: [LibraryItem], target: Target) {
        for section in nodes.sections {
            if let title = section.title {
                if !menu.items.isEmpty {
                    menu.addItem(.separator())
                }
                menu.addItem(NSMenuItem.sectionHeader(title: title))
            }
            for node in section.nodes {
                menu.addItem(item(for: node, target: target))
            }
        }
    }

    private static func item(for node: LibraryItem, target: Target) -> NSMenuItem {
        let item = NSMenuItem(title: node.name, action: nil, keyEquivalent: "")
        item.image = target.store.icon(for: node)
        if let children = node.children {
            let submenu = NSMenu()
            if children.isEmpty {
                let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                if node.showsOpenAllItem {
                    let openEach = NSMenuItem(title: "Open All", action: #selector(Target.openFolder(_:)), keyEquivalent: "")
                    openEach.target = target
                    openEach.representedObject = node.id
                    openEach.isEnabled = !openAllSelection(in: children).isEmpty
                    submenu.addItem(openEach)
                    submenu.addItem(.separator())
                }
                fill(submenu, with: children, target: target)
            }
            item.submenu = submenu
        } else {
            item.target = target
            item.action = #selector(Target.choose(_:))
            item.representedObject = node.id
            item.toolTip = node.url ?? node.command ?? node.appPath
            if let path = node.appPath, !FileManager.default.fileExists(atPath: path) {
                item.isEnabled = false
            }
        }
        return item
    }

    @MainActor
    private final class ClipTarget: NSObject {
        /// True when a text field had the keyboard, so choosing an item pastes it.
        let pastes: Bool
        /// The app that had the keyboard when the menu opened. A paste goes back to it.
        let previous: NSRunningApplication?

        init(pastes: Bool, returningTo previous: NSRunningApplication?) {
            self.pastes = pastes
            self.previous = previous
        }

        @objc func copy(_ sender: NSMenuItem) {
            if let item = clip(sender) {
                ClipboardLock.shared.perform(item, for: .copy) { [pastes, previous] in
                    ClipboardHistory.shared.copy(item)
                    if pastes { FrontApp.pasteSoon(returningTo: previous) }
                }
            }
        }

        @objc func copyPlain(_ sender: NSMenuItem) {
            if let item = clip(sender) {
                ClipboardLock.shared.perform(item, for: .copy) { [pastes, previous] in
                    ClipboardHistory.shared.copyPlainText(item)
                    if pastes { FrontApp.pasteSoon(returningTo: previous) }
                }
            }
        }

        @objc func addSuggested(_ sender: NSMenuItem) {
            if let suggestion = sender.representedObject as? AddSuggestion { LibraryStore.shared.add(suggestion) }
        }

        @objc func clear(_ sender: NSMenuItem) {
            ClipboardHistory.shared.clear()
        }

        @objc func pasteNext(_ sender: NSMenuItem) {
            ClipboardHistory.shared.pasteNext()
        }

        @objc func clearPasteQueue(_ sender: NSMenuItem) {
            ClipboardHistory.shared.clearPasteQueue()
        }

        private func clip(_ sender: NSMenuItem) -> ClipItem? {
            let id = sender.representedObject as? UUID
            return ClipboardHistory.shared.items.first { $0.id == id }
        }
    }

    @MainActor
    private final class Target: NSObject {
        let store: LibraryStore

        init(store: LibraryStore) {
            self.store = store
        }

        @objc func addSuggested(_ sender: NSMenuItem) {
            if let suggestion = sender.representedObject as? AddSuggestion { store.add(suggestion) }
        }

        @objc func choose(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID, let node = store.nodes.node(withID: id) else { return }
            // Holding Option flips the item's new-window or new-instance setting.
            let flip = NSEvent.modifierFlags.contains(.option)
            open(node, forceNew: flip ? node.openNew != true : nil)
        }

        @objc func openFolder(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID, let folder = store.nodes.node(withID: id) else { return }
            openAll(folder.children ?? [])
        }
    }
}
