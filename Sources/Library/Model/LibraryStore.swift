import CryptoKit
import Carbon
import SwiftUI

/// Where the menu shortcut shows the menu.
enum MenuMode: String {
    case cursor, menuBar
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var nodes: [LibraryItem] = [] {
        didSet {
            if !undoSuppressed {
                registerUndo(restoring: oldValue)
            }
            scheduleSave()
            scheduleIconFetch()
            registerHotKeys()
        }
    }
    @Published private var icons: [String: NSImage] = [:]
    /// Nodes whose shortcut the system rejected, usually because another app uses it.
    @Published private(set) var failedShortcuts: Set<UUID> = []
    /// Indexes of `extraHotkeys` the system rejected.
    @Published private(set) var failedExtras: Set<Int> = []
    /// How often each item was opened, by id. Preferences, not bookmark data.
    @Published private(set) var openCounts: [String: Int] = UserDefaults.standard.dictionary(forKey: "openCounts") as? [String: Int] ?? [:]
    /// Click shortcuts wait for Accessibility access.
    @Published private(set) var clickAccessMissing = false

    /// App preferences live in UserDefaults, not in bookmarks.json.
    /// What Restore Defaults sets: Control and right click for the menu, Control-Space for Quick Open, and
    /// Control-Command-V for the clipboard history menu.
    static let defaultHotkeys: [Shortcut?] = [
        Shortcut(modifiers: UInt32(controlKey), button: 1),
        Shortcut(keyCode: 49, modifiers: UInt32(controlKey), key: "Space"),
        nil,
        Shortcut(keyCode: 9, modifiers: UInt32(controlKey | cmdKey), key: "V"),
    ]

    /// The global shortcuts, by index: menu, Quick Open, open clipboard link, clipboard menu.
    @Published var extraHotkeys: [Shortcut?] = Array(repeating: nil, count: 4) {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(extraHotkeys), forKey: "extraHotkeys")
            registerHotKeys()
        }
    }
    @Published var menuMode: MenuMode {
        didSet { UserDefaults.standard.set(menuMode.rawValue, forKey: "menuMode") }
    }

    /// All of Library's data lives here, apart from the app, so updating or replacing the app never touches it.
    nonisolated static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".library")
    static let file = dir.appendingPathComponent("bookmarks.json")

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
    private static let fallbackIcon = symbol("link")
    private static let terminalIcon = symbol("terminal")
    private static let folderIcon = symbol("folder")
    private static let dividerIcon = symbol("minus.rectangle")

    private var fetchTask: Task<Void, Never>?
    private var accessTask: Task<Void, Never>?
    private var watcher: DispatchSourceFileSystemObject?
    /// True when bookmarks.json existed but could not be read, so the app can say so.
    private(set) var hadUnreadableFile = false
    private var saveTask: Task<Void, Never>?
    private var hotKeySignature = ""
    private var failedIcons: Set<String> = []
    private var lastSavedData: Data?
    private var undoSuppressed = false
    private var renameBase: [LibraryItem]?

    /// The manager window's undo manager. Edits made while it is nil are not undoable.
    var undoManager: UndoManager?

    /// Earlier versions kept data in Application Support. The first launch copies it to `~/.library` and leaves
    /// the old folder alone, as a backup.
    private static func copyLegacyData() {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ml-bookmarks")
        guard !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) else { return }
        try? fm.copyItem(at: legacy, to: dir)
    }

    init() {
        Self.copyLegacyData()
        let defaults = UserDefaults.standard
        func saved(_ key: String) -> Shortcut? {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        }
        // Older versions saved the menu and Quick Open shortcuts under their own keys.
        var hotkeys = defaults.data(forKey: "extraHotkeys").flatMap { try? JSONDecoder().decode([Shortcut?].self, from: $0) }
            ?? [saved("menuHotkey"), saved("paletteHotkey"), nil, nil]
        // The add-link shortcut was removed. Adding a copied link is an action in Quick Open now.
        let layout = defaults.integer(forKey: "hotkeyLayout")
        if layout < 2, hotkeys.count > 3 { hotkeys.remove(at: 3) }
        while hotkeys.count < 4 { hotkeys.append(nil) }
        // The clipboard menu gets its default once, so the feature can be found without setup.
        if layout < 3, hotkeys[3] == nil { hotkeys[3] = Self.defaultHotkeys[3] }
        if layout < 3 {
            defaults.set(3, forKey: "hotkeyLayout")
            defaults.set(try? JSONEncoder().encode(hotkeys), forKey: "extraHotkeys")
        }
        // Once, the menu and Quick Open get their default shortcuts if they have none. After that, clearing one sticks.
        let appliesDefaults = !defaults.bool(forKey: "defaultHotkeysApplied")
        if appliesDefaults {
            defaults.set(true, forKey: "defaultHotkeysApplied")
            for index in 0...1 where hotkeys[index] == nil { hotkeys[index] = Self.defaultHotkeys[index] }
            defaults.set(try? JSONEncoder().encode(hotkeys), forKey: "extraHotkeys")
        }
        extraHotkeys = hotkeys
        menuMode = UserDefaults.standard.string(forKey: "menuMode").flatMap(MenuMode.init) ?? .cursor
        // The folder holds saved clipboard text, so only you can read it.
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.dir.path)
        if let data = try? Data(contentsOf: Self.file) {
            if let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data) {
                nodes = decoded
            } else {
                hadUnreadableFile = true
                // The next edit overwrites bookmarks.json, so keep the unreadable file.
                let damaged = Self.dir.appendingPathComponent("bookmarks-damaged.json")
                try? FileManager.default.removeItem(at: damaged)
                try? FileManager.default.copyItem(at: Self.file, to: damaged)
            }
        } else {
            nodes = [LibraryItem(name: "GitHub", url: "https://github.com")]
            save()
        }
        HotKeys.onTapLost = { [weak self] in self?.registerHotKeys(force: true) }
        // Property observers do not run for assignments inside init.
        registerHotKeys()
        scheduleIconFetch()
        watchFile()
    }

    /// Sets the menu, Quick Open, and clipboard menu shortcuts back to their defaults. Open Link stays.
    func restoreDefaultHotkeys() {
        extraHotkeys = [Self.defaultHotkeys[0], Self.defaultHotkeys[1], extraHotkeys[2], Self.defaultHotkeys[3]]
        if clickAccessMissing { HotKeys.requestClickAccess() }
    }

    /// Reloads when bookmarks.json changes outside the app. The folder is watched because
    /// editors and git replace the file instead of writing into it.
    private func watchFile() {
        let descriptor = Darwin.open(Self.dir.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadIfChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func reloadIfChanged() {
        // The app's own saves match lastSavedData and are skipped. A change waiting to be saved wins.
        guard saveTask == nil, let data = try? Data(contentsOf: Self.file), data != lastSavedData,
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data) else { return }
        lastSavedData = data
        undoSuppressed = true
        nodes = decoded
        undoSuppressed = false
        // Old undo steps would restore the file from before the outside change.
        undoManager?.removeAllActions()
    }

    /// The web link on the clipboard, if there is one.
    private var clipboardLink: URL? {
        QuickOpenResult.link(from: NSPasteboard.general.string(forType: .string) ?? "")
    }

    /// Opens the copied link in the browser. A beep means the clipboard holds no link.
    func openClipboardLink() {
        guard let link = clipboardLink else { return NSSound.beep() }
        NSWorkspace.shared.open(link)
    }

    /// What the menus offer to add: the link selected in the front app, else what is on the clipboard.
    func suggestion(selection: String? = nil) -> AddSuggestion? {
        AddSuggestion.make(selection: selection, clipboard: ClipboardHistory.shared.current, in: nodes)
    }

    /// Adds a suggestion to the library, with a soft sound, as Safari does for a bookmark.
    func add(_ suggestion: AddSuggestion) {
        perform("Add to Library") { $0.append(suggestion.node, to: nil) }
        NSSound(named: "Pop")?.play()
    }

    /// Adds what a clipboard item holds to the library.
    func addToLibrary(_ item: ClipItem) {
        guard let node = item.libraryNode else { return NSSound.beep() }
        add(AddSuggestion(node: node, source: .clipboard))
    }

    func showQuickOpen() {
        QuickOpen.show(store: self)
    }

    /// The most opened items, for the Frequently Used section. Needs two or more opens.
    var frequent: [LibraryItem] {
        nodes.leaves
            .filter { (openCounts[$0.id.uuidString] ?? 0) >= 2 }
            .sorted { (openCounts[$0.id.uuidString] ?? 0) > (openCounts[$1.id.uuidString] ?? 0) }
            .prefix(5).map { $0 }
    }

    func recordOpen(_ id: UUID) {
        openCounts[id.uuidString, default: 0] += 1
        UserDefaults.standard.set(openCounts, forKey: "openCounts")
    }

    /// Opens the bookmarks menu from the menu shortcut.
    func showMenu() {
        if menuMode == .menuBar, PopupMenu.clickStatusItem() { return }
        // The selection is read now, while the app in front still has the keyboard.
        PopupMenu.show(store: self, selection: FrontApp.selectedText())
    }

    /// Registers again only when a shortcut changed, unless `force` is set. Registering touches the system.
    private func registerHotKeys(force: Bool = false) {
        let signature = "\(extraHotkeys)" + nodes.leaves.flatMap { node in
            (node.shortcuts ?? []).map { "\(node.id)\($0)" }
        }.joined()
        guard force || signature != hotKeySignature else { return }
        hotKeySignature = signature
        let result = HotKeys.register(nodes.leaves, extras: extraHotkeys) { [weak self] index in
            switch index {
            case 0: self?.showMenu()
            case 1: self?.showQuickOpen()
            case 2: self?.openClipboardLink()
            default: PopupMenu.showClipboard(selection: FrontApp.selectedText(), pastes: ClipboardHistory.shared.shouldPaste)
            }
        }
        failedShortcuts = result.nodes
        failedExtras = result.extras
        clickAccessMissing = result.needsAccess
        // The user grants access in System Settings, so check until it arrives.
        accessTask?.cancel()
        if result.needsAccess {
            accessTask = Task {
                while !Task.isCancelled && !HotKeys.hasClickAccess {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
                if !Task.isCancelled { registerHotKeys(force: true) }
            }
        }
    }

    /// The 16 pt icon: the custom icon, else by type: folder, divider, app icon, terminal, favicon, or link symbol.
    func icon(for node: LibraryItem) -> NSImage {
        let icon = baseIcon(for: node)
        guard let tint = node.color.flatMap({ LibraryItem.tagColors[$0] }) else { return icon }
        // The tag is a dot in the corner of the icon, so it shows in menus and lists alike.
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            icon.draw(in: rect)
            if icon.isTemplate {
                NSColor.labelColor.set()
                rect.fill(using: .sourceAtop)
            }
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: -1, width: 9, height: 9)).fill()
            tint.setFill()
            NSBezierPath(ovalIn: NSRect(x: 9, y: 0, width: 7, height: 7)).fill()
            return true
        }
    }

    private func baseIcon(for node: LibraryItem) -> NSImage {
        if let custom = node.icon.flatMap(customIcon) { return custom }
        if node.isFolder { return Self.folderIcon }
        if node.isDivider == true { return Self.dividerIcon }
        if let path = node.appPath { return appIcon(at: path) }
        if node.command != nil { return Self.terminalIcon }
        return icons[node.url ?? ""] ?? Self.fallbackIcon
    }

    /// Applies an edit as one undoable step named `actionName` in the Edit menu.
    func perform(_ actionName: String, _ change: (inout [LibraryItem]) -> Void) {
        change(&nodes)
        undoManager?.setActionName(actionName)
    }

    /// Renames without one undo step per keystroke. `endRename` records a single step.
    func rename(_ id: UUID, to name: String) {
        renameBase = renameBase ?? nodes
        undoSuppressed = true
        nodes.update(id) { $0.name = name }
        undoSuppressed = false
    }

    func endRename() {
        guard let base = renameBase else { return }
        renameBase = nil
        registerUndo(restoring: base)
        undoManager?.setActionName("Rename")
    }

    /// Moves nodes into folder `folderID`, or to the top level when `nil`.
    func move(_ ids: Set<UUID>, to folderID: UUID?) {
        if let folderID, !nodes.folders(skipping: ids).contains(where: { $0.id == folderID }) {
            return
        }
        perform("Move") { nodes in
            for node in Self.detach(ids, from: &nodes) {
                nodes.append(node, to: folderID)
            }
        }
    }

    /// Moves nodes to sit directly before node `targetID`.
    func move(_ ids: Set<UUID>, before targetID: UUID) {
        guard !ids.contains(where: { nodes.node(withID: $0)?.contains(targetID) == true }) else { return }
        perform("Move") { nodes in
            let moved = Self.detach(ids, from: &nodes)
            nodes.locate(targetID) { $0.insert(contentsOf: moved, at: $1) }
        }
    }

    /// Removes nodes from the tree and returns them in display order.
    private static func detach(_ ids: Set<UUID>, from nodes: inout [LibraryItem]) -> [LibraryItem] {
        nodes.allIDs.filter(ids.contains).compactMap { nodes.removeNode($0) }
    }

    /// Undoing assigns `nodes`, which registers the inverse step, so redo needs no extra code.
    private func registerUndo(restoring snapshot: [LibraryItem]) {
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.nodes = snapshot }
        }
    }

    /// Writes soon after the last change, so typing a name does not write the file for every key.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled {
                saveTask = nil
                save()
            }
        }
    }

    /// Writes a pending change now. The app calls this when it quits.
    func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(nodes) else { return }
        lastSavedData = data
        try? data.write(to: Self.file, options: .atomic)
    }

    /// Debounced so editing a URL does not fetch an icon per keystroke.
    private func scheduleIconFetch() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            let leaves = nodes.leaves
            indexInSpotlight(leaves)
            // Icons are collected and published once, since every publish redraws the menu. A site with no
            // icon is not asked again until the app restarts.
            var found: [String: NSImage] = [:]
            for node in leaves where !Task.isCancelled {
                guard let url = node.url, icons[url] == nil, !failedIcons.contains(url), let link = node.link else { continue }
                if let icon = await Favicon.load(for: link) {
                    found[url] = icon
                } else {
                    failedIcons.insert(url)
                }
            }
            if !found.isEmpty { icons.merge(found) { $1 } }
        }
    }

    /// Updates Spotlight only when what it shows changed, including since the last launch.
    private func indexInSpotlight(_ leaves: [LibraryItem]) {
        let signature = leaves.filter(\.isOpenable).map {
            "\($0.id)|\($0.name)|\($0.url ?? "")|\($0.command ?? "")|\($0.appPath ?? "")|\($0.keywords ?? "")|\($0.color ?? "")"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        guard digest != UserDefaults.standard.string(forKey: "spotlightDigest") else { return }
        UserDefaults.standard.set(digest, forKey: "spotlightDigest")
        Spotlight.index(leaves)
    }
}
