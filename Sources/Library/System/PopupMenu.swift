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
        fill(menu, with: store.nodes, target: target)
        if let suggestion = store.suggestion(selection: selection) {
            menu.addItem(.separator())
            menu.addItem(suggestionItem(suggestion, action: #selector(Target.addSuggested(_:)), target: target))
        }
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Shows the clipboard history at the mouse pointer. Choosing an item copies it back.
    static func showClipboard(selection: String? = nil, pastes: Bool = false) {
        let (menu, target) = makeClipboardMenu(history: .shared, suggestion: LibraryStore.shared.suggestion(selection: selection),
                                               pastes: pastes)
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// The clipboard history as a menu. The first nine items answer to the keys 1 to 9, and Option with the key
    /// picks Copy as Plain Text. The target receives the choices and must stay alive while the menu is open.
    static func makeClipboardMenu(history: ClipboardHistory, suggestion: AddSuggestion?,
                                  pastes: Bool) -> (menu: NSMenu, target: NSObject) {
        let target = ClipTarget(pastes: pastes)
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
                let item = NSMenuItem(title: clip.menuTitle, action: #selector(ClipTarget.copy(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = []
                item.target = target
                item.representedObject = clip.id
                item.image = clip.icon
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
                let openEach = NSMenuItem(title: "Open All", action: #selector(Target.openFolder(_:)), keyEquivalent: "")
                openEach.target = target
                openEach.representedObject = node.id
                openEach.isEnabled = !openAllSelection(in: children).isEmpty
                submenu.addItem(openEach)
                submenu.addItem(.separator())
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

        init(pastes: Bool) {
            self.pastes = pastes
        }

        @objc func copy(_ sender: NSMenuItem) {
            if let item = clip(sender) {
                ClipboardHistory.shared.copy(item)
                if pastes { FrontApp.pasteSoon() }
            }
        }

        @objc func copyPlain(_ sender: NSMenuItem) {
            if let item = clip(sender) {
                ClipboardHistory.shared.copyPlainText(item)
                if pastes { FrontApp.pasteSoon() }
            }
        }

        @objc func addSuggested(_ sender: NSMenuItem) {
            if let suggestion = sender.representedObject as? AddSuggestion { LibraryStore.shared.add(suggestion) }
        }

        @objc func clear(_ sender: NSMenuItem) {
            ClipboardHistory.shared.clear()
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
