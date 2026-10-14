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

    /// The library and Recently Deleted together, so one undo step can change both.
    @Published private(set) var contents = LibrarySync.Contents() {
        didSet {
            revision += 1
            if !undoSuppressed {
                registerUndo(restoring: oldValue)
            }
            // Changes read from disk are already saved, so writing them back would only reformat the file.
            if !loadingFromDisk { scheduleSave() }
            // Only the previous fingerprint is kept, so an edit builds one new fingerprint, not two.
            let previous = fingerprint
            fingerprint = TreeFingerprint(nodes)
            if needsIconFetch(old: previous, new: fingerprint) { scheduleIconFetch() }
            scheduleSpotlightIndex()
            if needsHotKeyRegistration(old: previous, new: fingerprint) { registerHotKeys() }
        }
    }
    /// The live items: what the menus, Quick Open, the hot keys, and Spotlight use.
    var nodes: [LibraryItem] {
        get { contents.live }
        set { contents.live = newValue }
    }
    /// Items deleted in the last 30 days, top level only, each with its subtree. Shown in Recently Deleted.
    var deleted: [LibraryItem] { contents.deleted }
    /// Counts every change to `nodes` and `deleted`, so a cached search knows when the library changed.
    private(set) var revision = 0
    /// The fields of `nodes` that the follow-up work depends on. Matches `nodes` at all times.
    private var fingerprint = TreeFingerprint([])
    @Published private var icons: [String: NSImage] = [:]
    /// Nodes whose shortcut the system rejected, usually because another app uses it.
    @Published private(set) var failedShortcuts: Set<UUID> = []
    /// Indexes of `extraHotkeys` the system rejected.
    @Published private(set) var failedExtras: Set<Int> = []
    /// How often each item was opened, by id. Preferences, not bookmark data.
    @Published private(set) var openCounts: [String: Int] = UserDefaults.standard.dictionary(forKey: "openCounts") as? [String: Int] ?? [:]
    /// Click shortcuts wait for Accessibility access.
    @Published private(set) var clickAccessMissing = false
    /// True when bookmarks.json is kept in iCloud Drive. Settings > General shows it.
    @Published private(set) var keepsInICloud = LibrarySync.isLinked(LibraryStore.file)
    /// True when bookmarks.json is linked to an iCloud copy that is gone. Library changes nothing until it is back.
    private(set) var cloudFileMissing = false
    /// The iCloud copy's state for the manager footer. Nil when the library is not in iCloud Drive.
    @Published private(set) var syncState: LibrarySync.SyncState?

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
    /// `LIBRARY_HOME` moves this folder elsewhere. The render harness (Tests/render.sh) uses it so it never reads or
    /// writes your library. Normally it is unset.
    nonisolated static let dir: URL = {
        let home = ProcessInfo.processInfo.environment["LIBRARY_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return (home ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(".library")
    }()
    nonisolated static var redirected: Bool { ProcessInfo.processInfo.environment["LIBRARY_HOME"] != nil }
    static let file = dir.appendingPathComponent("bookmarks.json")
    /// Where saves go. Normally `file`. With iCloud Drive on, `file` is a link and this is the iCloud copy, so a save
    /// writes through the link instead of replacing it.
    static var dataFile: URL { LibrarySync.linkDestination(of: file) ?? file }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
    private static let fallbackIcon = symbol("link")
    private static let terminalIcon = symbol("terminal")
    private static let folderIcon = symbol("folder")
    private static let dividerIcon = symbol("minus.rectangle")

    private var fetchTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?
    private var accessTask: Task<Void, Never>?
    private var syncStateTask: Task<Void, Never>?
    private var watchers: [DispatchSourceFileSystemObject] = []
    /// True when bookmarks.json existed but could not be read, so the app can say so.
    private(set) var hadUnreadableFile = false
    /// True when bookmarks.json exists but cannot be read. Library does not write over it until it can be read.
    private(set) var fileReadFailed = false
    private var saveBlocked = false
    private var saveFailureShown = false
    private var saveTask: Task<Void, Never>?
    private var hotKeyLayout: HotKeyLayout?
    private var failedIcons: Set<String> = []
    /// Modification date and size of bookmarks.json when it was last read or written.
    private var lastFileStamp: String?
    /// The bytes of bookmarks.json when it was last read or written. A different file on disk is another Mac's version.
    private var lastSavedData: Data?
    /// Reports changes to the iCloud copy. Registered only while the library is in iCloud Drive.
    private var presenter: LibraryFilePresenter?
    /// True while a conflict is on screen, so a second one does not open over it.
    private var presentingConflict = false
    private var undoSuppressed = false
    private var loadingFromDisk = false
    private var renameBase: LibrarySync.Contents?

    /// The shortcuts that register: the extras, and each item's shortcuts with the item they open.
    private struct HotKeyLayout: Equatable {
        struct Binding: Equatable {
            let node: UUID
            let shortcut: Shortcut
        }
        let extras: [Shortcut?]
        let bindings: [Binding]
    }

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
        if LibrarySync.isDanglingLink(Self.file) {
            // The iCloud copy is gone. A default library must not replace it, so nothing is written until it is back.
            cloudFileMissing = true
            fileReadFailed = true
            saveBlocked = true
            if LibrarySync.isEvicted(Self.dataFile) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: Self.dataFile)
            }
        } else {
            switch BookmarkFile.load(from: Self.file) {
            case .loaded(let items):
                contents = LibrarySync.Contents(file: items)
                lastFileStamp = fileStamp()
                lastSavedData = try? LibrarySync.read(Self.dataFile)
            case .missing:
                // A new install starts with the project's page, so the library shows how a bookmark looks and works.
                nodes = [LibraryItem(name: "Library on GitHub", url: "https://github.com/deansasek/library", keywords: "library help")]
                save()
            case .unreadable:
                // Nothing is written over a file that could not be read, so the next edit does not replace it.
                fileReadFailed = true
                saveBlocked = true
            case .damaged:
                hadUnreadableFile = true
                // The next edit overwrites bookmarks.json, so keep the unreadable file.
                let damaged = Self.dir.appendingPathComponent("bookmarks-damaged.json")
                try? FileManager.default.removeItem(at: damaged)
                try? FileManager.default.copyItem(at: Self.file, to: damaged)
            }
        }
        HotKeys.onTapLost = { [weak self] in self?.registerHotKeys(force: true) }
        // Property observers do not run for assignments inside init.
        fingerprint = TreeFingerprint(nodes)
        registerHotKeys()
        scheduleIconFetch()
        scheduleSpotlightIndex()
        watchFile()
        if LibrarySync.isLinked(Self.file), !cloudFileMissing {
            startPresenting()
            refreshSyncState()
            scheduleConflictCheck()
        }
    }

    /// Sets the menu, Quick Open, and clipboard menu shortcuts back to their defaults. Open Link stays.
    func restoreDefaultHotkeys() {
        extraHotkeys = [Self.defaultHotkeys[0], Self.defaultHotkeys[1], extraHotkeys[2], Self.defaultHotkeys[3]]
        if clickAccessMissing { HotKeys.requestClickAccess() }
    }

    /// Reloads when bookmarks.json changes outside the app. The folder is watched because
    /// editors and git replace the file instead of writing into it. Other files in the folder are ignored.
    /// With iCloud Drive on, changes to the iCloud copy come through `presenter` instead. Nothing polls.
    private func watchFile() {
        watchers.forEach { $0.cancel() }
        watchers = []
        for folder in [Self.dir] {
            let descriptor = Darwin.open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.reloadIfChanged() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers.append(source)
        }
    }

    private func reloadIfChanged() {
        // Most events are for other files in the folder, so the file's stamp is checked before its contents.
        let stamp = fileStamp()
        guard saveTask == nil, !presentingConflict, stamp != lastFileStamp,
              LibrarySync.unresolvedConflicts(at: Self.dataFile).isEmpty,
              let data = try? LibrarySync.read(Self.dataFile, presenter: presenter), data != lastSavedData,
              let decoded = LibrarySync.decode(data) else { return }
        lastFileStamp = stamp
        adopt(decoded, data: data)
    }

    /// Makes `items`, read from disk, the library. Old undo steps are dropped, since they would restore the file
    /// from before the outside change.
    private func adopt(_ items: LibrarySync.Contents, data: Data) {
        lastSavedData = data
        fileReadFailed = false
        cloudFileMissing = false
        hadUnreadableFile = false
        saveBlocked = false
        saveFailureShown = false
        undoSuppressed = true
        loadingFromDisk = true
        contents = items
        loadingFromDisk = false
        undoSuppressed = false
        undoManager?.removeAllActions()
    }

    /// Records that the file now matches the library, so later edits are the only unsynced changes.
    private func markSynced() {
        lastFileStamp = fileStamp()
        lastSavedData = try? LibrarySync.read(Self.dataFile, presenter: presenter)
        refreshSyncState()
    }

    /// Starts reporting changes to the iCloud copy. Called once the library is linked to iCloud Drive.
    private func startPresenting() {
        guard presenter == nil else { return }
        let presenter = LibraryFilePresenter(url: Self.dataFile)
        presenter.onChange = { [weak self] in self?.fileChangedElsewhere() }
        self.presenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func stopPresenting() {
        guard let presenter else { return }
        NSFileCoordinator.removeFilePresenter(presenter)
        self.presenter = nil
    }

    /// Another Mac, or iCloud, changed the file. The file is read unless a save or a conflict is pending, and a
    /// conflict is shown when there is one.
    private func fileChangedElsewhere() {
        reloadIfChanged()
        refreshSyncState()
        scheduleConflictCheck()
    }

    /// Checks for a conflict after the current event, so an alert does not open inside the file coordinator's callback.
    private func scheduleConflictCheck() {
        Task { @MainActor in
            _ = checkForConflicts()
        }
    }

    /// Shows the conflict when there is one. Returns true when it did, or when a conflict is pending but unreadable.
    @discardableResult
    private func checkForConflicts() -> Bool {
        guard !presentingConflict, !saveBlocked, let others = otherVersions() else { return false }
        guard !others.isEmpty else { return false }
        resolveConflicts(others)
        return true
    }

    /// Asks what to keep, and keeps it. Each choice is written before the conflict versions are marked resolved.
    private func resolveConflicts(_ others: [(contents: LibrarySync.Contents, date: Date)]) {
        guard !presentingConflict else { return }
        presentingConflict = true
        defer { presentingConflict = false }
        let versions = LibrarySync.unresolvedConflicts(at: Self.dataFile)
        let other = others[0].contents
        while true {
            switch askWhichVersionToKeep() {
            case .thisMac:
                return finishConflict(LibrarySync.resolve(local: contents, other: other, preferring: .thisMac, choices: [:]), versions)
            case .other:
                return finishConflict(LibrarySync.resolve(local: contents, other: other, preferring: .other, choices: [:]), versions)
            case .review:
                let differences = LibrarySync.differences(local: contents, other: other)
                if let picks = ConflictReview.run(differences) {
                    return finishConflict(LibrarySync.resolve(local: contents, other: other, preferring: .thisMac, choices: picks), versions)
                }
            }
        }
    }

    private func finishConflict(_ resolved: LibrarySync.Contents, _ versions: [NSFileVersion]) {
        undoSuppressed = true
        loadingFromDisk = true
        contents = resolved
        loadingFromDisk = false
        undoSuppressed = false
        undoManager?.removeAllActions()
        guard writeLibrary() else { return }
        guard !versions.isEmpty else { return }
        do {
            try LibrarySync.resolveConflicts(versions, at: Self.dataFile)
        } catch {
            reportSaveFailure("The other version of bookmarks.json in iCloud Drive couldn’t be cleared. Library will ask again. \(error.localizedDescription)")
        }
    }

    /// The versions that differ from this Mac's library and are not resolved: iCloud's unresolved conflict versions,
    /// and a file on disk that another Mac wrote after this Mac's last read or write. Nil when a version exists
    /// but cannot be read yet.
    private func otherVersions() -> [(contents: LibrarySync.Contents, date: Date)]? {
        guard LibrarySync.isLinked(Self.file) else { return [] }
        var others: [(contents: LibrarySync.Contents, date: Date)] = []
        for version in LibrarySync.unresolvedConflicts(at: Self.dataFile) {
            guard let data = try? LibrarySync.read(version.url), let decoded = LibrarySync.decode(data) else { return nil }
            others.append((decoded, version.modificationDate ?? .distantPast))
        }
        if let data = try? LibrarySync.read(Self.dataFile, presenter: presenter), data != lastSavedData {
            guard let decoded = LibrarySync.decode(data) else { return nil }
            if decoded != contents { others.append((decoded, Date())) }
        }
        return others.sorted { $0.date > $1.date }
    }

    private enum VersionChoice {
        case thisMac, other, review
    }

    /// The standard document conflict alert. Keep This Mac's Version is the default.
    private func askWhichVersionToKeep() -> VersionChoice {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Two versions of your library were edited on different Macs"
        alert.informativeText = "Keep one version. Review lists each item that differs, so you can choose for each one."
        alert.addButton(withTitle: "Keep This Mac’s Version")
        alert.addButton(withTitle: "Keep the Other Version")
        alert.addButton(withTitle: "Review")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .thisMac
        case .alertSecondButtonReturn: return .other
        default: return .review
        }
    }

    private func fileStamp() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Self.dataFile.path) else { return nil }
        return "\(attributes[.modificationDate] ?? "")|\(attributes[.size] ?? "")"
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
        let layout = HotKeyLayout(extras: extraHotkeys, bindings: nodes.leaves.flatMap { node in
            (node.shortcuts ?? []).map { HotKeyLayout.Binding(node: node.id, shortcut: $0) }
        })
        guard force || layout != hotKeyLayout else { return }
        hotKeyLayout = layout
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
            // The ring matches the menu background, so it reads in light and dark menus.
            NSColor.windowBackgroundColor.setFill()
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
        var edited = nodes
        change(&edited)
        nodes = edited
        undoManager?.setActionName(actionName)
    }

    /// Applies an edit to the library and Recently Deleted as one undoable step named `actionName`.
    private func edit(_ actionName: String, _ change: (inout LibrarySync.Contents) -> Void) {
        var edited = contents
        change(&edited)
        contents = edited
        undoManager?.setActionName(actionName)
    }

    /// Moves items to Recently Deleted. Folders take their contents with them.
    func delete(_ ids: Set<UUID>) {
        edit("Delete") { LibrarySync.tombstone(ids, in: &$0, at: Date()) }
    }

    /// Puts deleted items back: into their folder when it still exists, else to the top level.
    func restore(_ ids: Set<UUID>) {
        edit("Restore") { LibrarySync.restore(ids, in: &$0) }
    }

    /// Removes deleted items for good. The caller confirms first.
    func deleteImmediately(_ ids: Set<UUID>) {
        edit("Delete Immediately") { LibrarySync.deleteImmediately(ids, in: &$0) }
    }

    /// Renames without one undo step per keystroke. `endRename` records a single step.
    func rename(_ id: UUID, to name: String) {
        renameBase = renameBase ?? contents
        undoSuppressed = true
        var edited = nodes
        edited.update(id) { $0.name = name }
        nodes = edited
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
    private func registerUndo(restoring snapshot: LibrarySync.Contents) {
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.contents = snapshot }
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
        guard !saveBlocked else {
            return reportSaveFailure("bookmarks.json can’t be read, so your changes aren’t saved. Check the file’s permissions. Library saves again once the file can be read.")
        }
        guard !presentingConflict else { return }
        // Nothing is written over another version. A conflict is resolved first, with the user's choice.
        guard let others = otherVersions() else {
            return reportSaveFailure("bookmarks.json in iCloud Drive can’t be read yet, so your changes aren’t saved. Library saves again when iCloud has the file.")
        }
        guard others.isEmpty else { return resolveConflicts(others) }
        writeLibrary()
    }

    /// Writes the library through NSFileCoordinator. Returns false, after an alert, when the write fails.
    @discardableResult
    private func writeLibrary() -> Bool {
        purgeExpired()
        let encoded: Data
        do {
            encoded = try LibrarySync.encode(contents)
        } catch {
            reportSaveFailure("Library couldn’t prepare your library for saving.")
            return false
        }
        do {
            try LibrarySync.write(encoded, to: Self.dataFile, presenter: presenter)
            // An atomic write creates the file with the default mode (0644). Only you can read it.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.dataFile.path)
        } catch {
            reportSaveFailure(error.localizedDescription)
            return false
        }
        lastSavedData = encoded
        lastFileStamp = fileStamp()
        saveFailureShown = false
        refreshSyncState()
        return true
    }

    /// Removes the Recently Deleted items older than 30 days. Not an undo step.
    private func purgeExpired() {
        var purged = contents
        LibrarySync.purge(&purged, now: Date())
        guard purged != contents else { return }
        undoSuppressed = true
        loadingFromDisk = true
        contents = purged
        loadingFromDisk = false
        undoSuppressed = false
    }

    /// Re-reads the iCloud copy's state now, and again shortly while it is still uploading or waiting, so the footer
    /// catches up without a watcher. Stops after about a minute.
    func refreshSyncState() {
        syncState = keepsInICloud ? LibrarySync.syncState(of: Self.dataFile) : nil
        guard let state = syncState, state != .upToDate else { return }
        syncStateTask?.cancel()
        syncStateTask = Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.syncState = self.keepsInICloud ? LibrarySync.syncState(of: Self.dataFile) : nil
                if self.syncState == nil || self.syncState == .upToDate { return }
            }
        }
    }

    /// Turns the iCloud Drive storage on or off, from the Settings toggle. A failure shows an alert and changes nothing.
    func setKeepsInICloud(_ on: Bool) {
        guard on != keepsInICloud, !Self.redirected else { return }
        if on { turnOnICloud() } else { turnOffICloud() }
    }

    private func turnOnICloud() {
        let fm = FileManager.default
        save()
        guard !saveBlocked, fm.fileExists(atPath: Self.file.path), !LibrarySync.isLinked(Self.file) else {
            showSyncAlert("Library Couldn’t Turn On iCloud Drive", "Library can’t save bookmarks.json right now, so it stays on this Mac. Nothing was changed.")
            return
        }
        let iCloud = LibrarySync.iCloudFolder
        let cloud = LibrarySync.cloudFile(in: iCloud)
        guard !LibrarySync.isEvicted(cloud) else {
            showSyncAlert("Library Can’t Use iCloud Drive Yet", "The library in iCloud Drive hasn’t finished downloading. Try again in a few minutes. Nothing was changed.")
            return
        }
        let prompt = LibrarySync.enablePrompt(iCloudFolderExists: fm.fileExists(atPath: iCloud.path),
                                              cloudFileExists: fm.fileExists(atPath: cloud.path))
        var choice = LibrarySync.Choice.useThisMac
        switch prompt {
        case .unavailable:
            showSyncAlert("iCloud Drive Isn’t Available", "Turn on iCloud Drive in System Settings, then turn this on again. Your library stays on this Mac.")
            return
        case .move:
            break
        case .askWhichToKeep:
            guard let picked = askWhichLibraryToKeep(), picked != .cancel else { return }
            choice = picked
        }
        if choice == .useICloud, LibrarySync.decode((try? LibrarySync.read(cloud)) ?? Data()) == nil {
            showSyncAlert("Library Can’t Read the iCloud Library", "The bookmarks.json in iCloud Drive can’t be read, so Library keeps this Mac’s library. Nothing was changed.")
            return
        }
        let steps = LibrarySync.enableSteps(
            local: Self.file, cloud: cloud,
            backupLocal: Self.dir.appendingPathComponent("bookmarks-before-iCloud.json"),
            backupCloud: Self.dir.appendingPathComponent("bookmarks-iCloud-replaced.json"),
            prompt: prompt, choice: choice)
        do {
            try LibrarySync.run(steps)
        } catch {
            LibrarySync.recover(local: Self.file, cloud: cloud)
            showSyncAlert("Library Couldn’t Turn On iCloud Drive", error.localizedDescription)
            return
        }
        if choice == .useICloud, let data = try? LibrarySync.read(Self.dataFile), let items = LibrarySync.decode(data) {
            adopt(items, data: data)
        }
        keepsInICloud = true
        markSynced()
        watchFile()
        startPresenting()
        scheduleConflictCheck()
    }

    private func turnOffICloud() {
        guard !cloudFileMissing, !saveBlocked else {
            showSyncAlert("Library Couldn’t Turn Off iCloud Drive", "The library in iCloud Drive can’t be read, so it stays there. Nothing was changed.")
            return
        }
        // Writes any pending change and merges what another Mac saved, so the copy made below is the current library.
        save()
        guard !saveBlocked, let cloud = LibrarySync.linkDestination(of: Self.file),
              FileManager.default.fileExists(atPath: cloud.path) else {
            showSyncAlert("Library Couldn’t Turn Off iCloud Drive", "The library in iCloud Drive can’t be read, so it stays there. Nothing was changed.")
            return
        }
        // Stops watching the iCloud copy while its steps remove it, so Library does not react to its own change.
        stopPresenting()
        do {
            try LibrarySync.run(LibrarySync.disableSteps(local: Self.file, cloud: cloud))
        } catch {
            LibrarySync.recover(local: Self.file, cloud: cloud)
            startPresenting()
            showSyncAlert("Library Couldn’t Turn Off iCloud Drive", error.localizedDescription)
            return
        }
        keepsInICloud = false
        markSynced()
        watchFile()
    }

    /// Asks which library stays when iCloud Drive and this Mac both have one. Cancel is the default button, since the
    /// other choice replaces a library.
    private func askWhichLibraryToKeep() -> LibrarySync.Choice? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Keep Which Library?"
        alert.informativeText = "iCloud Drive already has a library. Use the iCloud Library to switch to it, or use This Mac’s Library to replace it. Library keeps a backup of the library it replaces in ~/.library."
        alert.addButton(withTitle: "Use the iCloud Library")
        alert.addButton(withTitle: "Use This Mac’s Library")
        let cancel = alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .useICloud
        case .alertSecondButtonReturn: return .useThisMac
        default: return nil
        }
    }

    private func showSyncAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Shows a save failure once, until a save works again, so a failing disk does not open an alert per edit.
    private func reportSaveFailure(_ reason: String) {
        NSLog("Library could not save bookmarks.json: \(reason)")
        guard !saveFailureShown else { return }
        saveFailureShown = true
        // Shown on the next pass of the run loop, so the alert does not open in the middle of a save.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Library Couldn’t Save Your Changes"
            alert.informativeText = reason
            alert.runModal()
        }
    }

    /// Debounced so editing a URL does not fetch an icon per keystroke. Up to `iconConcurrency` sites are fetched at once.
    private func scheduleIconFetch() {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            // A redirected library (LIBRARY_HOME) is a test copy: it neither indexes Spotlight nor fetches icons.
            if Self.redirected { return }
            let leaves = nodes.leaves
            // Icons are collected and published once, since every publish redraws the menu. A site with no
            // icon is not asked again until the app restarts.
            var seen = Set<String>()
            let pending = leaves.compactMap { node -> (url: String, link: URL)? in
                guard let url = node.url, icons[url] == nil, !failedIcons.contains(url), let link = node.link,
                      seen.insert(url).inserted else { return nil }
                return (url, link)
            }
            var found: [String: NSImage] = [:]
            await withTaskGroup(of: (String, NSImage?).self) { group in
                var next = pending.makeIterator()
                func startNext() {
                    guard !Task.isCancelled, let item = next.next() else { return }
                    group.addTask { (item.url, await Favicon.load(for: item.link)) }
                }
                for _ in 0..<Self.iconConcurrency { startNext() }
                for await (url, icon) in group {
                    if let icon {
                        found[url] = icon
                    } else if !Task.isCancelled {
                        failedIcons.insert(url)
                    }
                    startNext()
                }
            }
            if !found.isEmpty { icons.merge(found) { $1 } }
            // Icons for bookmarks that were deleted or re-addressed are dropped, so the dictionary does not grow
            // for the whole session. Published only when something was removed, since each publish redraws.
            let live = Set(nodes.leaves.compactMap(\.url))
            if icons.keys.contains(where: { !live.contains($0) }) { icons = retainedIcons(icons, live: live) }
        }
    }

    private static let iconConcurrency = 4

    /// Spotlight shows names too, so every edit schedules a check. It runs on its own debounce, so an icon
    /// fetch is not restarted for a rename.
    private func scheduleSpotlightIndex() {
        spotlightTask?.cancel()
        spotlightTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            indexInSpotlight(nodes.leaves)
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

/// The fields of a library that the store's follow-up work depends on: every field of every item except its name,
/// in display order, and the shortcut bindings that hot keys register. Names are left out because only Spotlight
/// shows them, so renaming an item does not restart icon fetches or hot key registration.
struct TreeFingerprint: Equatable {
    struct Entry: Equatable {
        let id: UUID
        let isFolder: Bool
        let url: String?
        let appPath: String?
        let arguments: String?
        let command: String?
        let shortcuts: [Shortcut]?
        let keywords: String?
        let color: String?
        let icon: String?
        let browser: String?
        let promptLabel: String?
        let templateFields: [String]?
        let isDivider: Bool?
        let openNew: Bool?
        let openAtLogin: Bool?

        init(_ node: LibraryItem) {
            id = node.id
            isFolder = node.isFolder
            url = node.url
            appPath = node.appPath
            arguments = node.arguments
            command = node.command
            shortcuts = node.shortcuts
            keywords = node.keywords
            color = node.color
            icon = node.icon
            browser = node.browser
            promptLabel = node.promptLabel
            templateFields = node.templateFields
            isDivider = node.isDivider
            openNew = node.openNew
            openAtLogin = node.openAtLogin
        }
    }

    /// One shortcut and the item it opens. Hot keys register from these, and only these, in order.
    struct Binding: Equatable {
        let node: UUID
        let shortcut: Shortcut
    }

    let entries: [Entry]
    let bindings: [Binding]

    init(_ nodes: [LibraryItem]) {
        var entries: [Entry] = []
        var bindings: [Binding] = []
        func visit(_ list: [LibraryItem]) {
            for node in list {
                entries.append(Entry(node))
                if let children = node.children {
                    visit(children)
                } else {
                    bindings += (node.shortcuts ?? []).map { Binding(node: node.id, shortcut: $0) }
                }
            }
        }
        visit(nodes)
        self.entries = entries
        self.bindings = bindings
    }
}

/// True when a change from `old` to `new` can change what icon fetching sees: anything but a name.
func needsIconFetch(old: TreeFingerprint, new: TreeFingerprint) -> Bool {
    old.entries != new.entries
}

/// True when a change from `old` to `new` can change the hot keys: the shortcuts and the items they open.
func needsHotKeyRegistration(old: TreeFingerprint, new: TreeFingerprint) -> Bool {
    old.bindings != new.bindings
}
