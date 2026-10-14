import Combine
import SwiftUI

@MainActor
final class QuickOpenModel: ObservableObject {
    let store: LibraryStore
    /// Searched when the text changes, not on every redraw.
    @Published var query = "" {
        didSet { scheduleResults() }
    }
    /// The recompute waiting for typing to settle. Each change to the query cancels the one before.
    private var resultsTask: Task<Void, Never>?
    /// The library's search index. Nil when the library changed since it was built, and rebuilt on the next search.
    private var index: QuickOpenIndex?
    /// Counts changes to the library, so cached lists that depend on it are rebuilt.
    private var nodesVersion = 0
    private var nodesObserver: AnyCancellable?
    private var snippetsObserver: AnyCancellable?
    /// The most opened items, kept until the open counts or the library change.
    private var frequentCache: (counts: [String: Int], version: Int, items: [LibraryItem])?
    @Published private(set) var results: [QuickOpenResult] = []
    @Published var selection: String? {
        didSet {
            refreshPreview()
            // A locked pinned item is not previewed until the user asks for it.
            ClipPreview.shared.follow(selected?.clip.flatMap { ClipboardLock.shared.isHidden($0) ? nil : $0 })
        }
    }
    private var animatedImages: [UUID: NSImage] = [:]

    /// The playing image for a copied GIF, decoded once and kept while the panel is open.
    func animatedImage(for item: ClipItem) -> NSImage? {
        // The row holds a copy from when the list was built. A GIF may have finished downloading since.
        let item = ClipboardHistory.shared.items.first { $0.id == item.id } ?? item
        guard !ClipboardLock.shared.isHidden(item), item.isAnimated else { return nil }
        if let cached = animatedImages[item.id] { return cached }
        let image = item.loadAnimated()
        animatedImages[item.id] = image
        return image
    }
    /// True when the pointer chose the selection, so the list does not scroll under it.
    private(set) var selectedByHover = false
    private var lastMouse = NSEvent.mouseLocation
    /// Set while a row is being dragged out, so the panel can close once it is dropped.
    var isDragging = false
    /// The picture shown in the preview, decoded once per selection.
    @Published private(set) var previewImage: NSImage?
    /// Tab swaps the results for the actions of the selected item.
    @Published var showActions = false
    @Published var actionSelection = 0
    /// Drives the entrance: the card fades and grows in once the panel is placed.
    @Published var appeared = false

    private var historyObserver: AnyCancellable?
    private var lockObserver: AnyCancellable?

    /// The text selected in the app that was in front when Quick Open opened. It can suggest adding a link.
    private let selectedText: String?

    /// True when a text field had the keyboard when Quick Open opened. Choosing a clipboard item pastes it then.
    private let pastes: Bool

    init(store: LibraryStore, selectedText: String?, pastes: Bool) {
        self.store = store
        self.selectedText = selectedText
        self.pastes = pastes
        // Any change to the library drops the index and the frequent list. Both are rebuilt when next needed.
        nodesObserver = store.$nodes.dropFirst().sink { [weak self] _ in
            self?.index = nil
            self?.nodesVersion += 1
        }
        // Snippets are part of the search index, so a change to them rebuilds it too.
        snippetsObserver = SnippetStore.shared.$snippets.dropFirst().sink { [weak self] _ in
            self?.index = nil
        }
        results = computeResults()
        // A copied GIF finishing its download updates the open panel.
        historyObserver = ClipboardHistory.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send()
            self?.refreshPreview()
        }
        // Unlocking or locking a pinned item changes what the rows and the preview show.
        lockObserver = ClipboardLock.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send()
            self?.refreshPreview()
        }
    }

    /// Space previews the selected clip in Quick Look, or closes the preview if it is open. Returns false, so Space
    /// types a space, when the search has text and the selection is not a clip, or when there is nothing to preview.
    /// A locked pinned item asks for authentication first, and Space is used up by that.
    func togglePreview() -> Bool {
        guard !showActions, query.isEmpty || selected?.clip != nil, let item = selected?.clip else { return false }
        if ClipboardLock.shared.isHidden(item) {
            ClipboardLock.shared.perform(item, for: .show) { ClipPreview.shared.toggle(item) }
            return true
        }
        return ClipPreview.shared.toggle(item)
    }

    /// Shows a locked pinned item's text in the preview, once the user authenticates.
    func reveal(_ item: ClipItem) {
        ClipboardLock.shared.perform(item, for: .show) {}
    }

    private func refreshPreview() {
        previewImage = selected?.clip.flatMap { clip -> NSImage? in
            guard !ClipboardLock.shared.isHidden(clip) else { return nil }
            return animatedImage(for: clip) ?? clip.image
        }
    }

    /// How long a query change waits before the results are recomputed. Nil means now: a blank query shows the
    /// browse list at once. Otherwise one display frame, so keystrokes that arrive together cost one search.
    nonisolated static func recomputeDelay(for query: String) -> Duration? {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .milliseconds(16)
    }

    private func scheduleResults() {
        resultsTask?.cancel()
        guard let delay = Self.recomputeDelay(for: query) else {
            resultsTask = nil
            results = computeResults()
            return
        }
        resultsTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.results = self.computeResults()
            // The view resets the selection when the query changes, before this recompute. Reset it again so it
            // lands on the first of the new results.
            self.resetSelection()
        }
    }

    /// The library's index, built on first use after the library changed.
    private func searchIndex() -> QuickOpenIndex {
        if let index { return index }
        let built = QuickOpenIndex(nodes: store.nodes, snippets: SnippetStore.shared.snippets)
        index = built
        return built
    }

    /// The top of Frequently Used, recomputed only when the open counts or the library change.
    private func frequentItems() -> [LibraryItem] {
        let counts = store.openCounts
        if let cache = frequentCache, cache.version == nodesVersion, cache.counts == counts { return cache.items }
        let items = store.frequent
        frequentCache = (counts, nodesVersion, items)
        return items
    }

    private func computeResults() -> [QuickOpenResult] {
        let text = query.trimmingCharacters(in: .whitespaces)
        var list = searchIndex().search(text, counts: store.openCounts)
        guard !text.isEmpty else {
            // The same Frequently Used section the menu has, first. Its ids differ from the library rows' ids,
            // so an item can sit in both without clashing.
            var frequent = frequentItems().map { QuickOpenResult(kind: .item($0, folder: ""), id: "\($0.id.uuidString)#frequent") }
            if !frequent.isEmpty { frequent[0].section = "Frequently Used" }
            return suggestion(section: "Suggested") + frequent + list
                + clipboardResults(ClipboardHistory.shared.displayOrder.prefix(5))
        }
        list += clipboardResults(ClipboardHistory.shared.search(text).prefix(8))
        // Typing "add" or part of "add to library" also offers the copied link or application.
        if text.count >= 2, "add to library".contains(text.lowercased()) {
            list = suggestion(section: nil) + list
        }
        if let link = QuickOpenResult.link(from: text) {
            list.insert(QuickOpenResult(kind: .openLink(link), id: "open"), at: 0)
            list.append(QuickOpenResult(kind: .addLink(link), id: "add"))
        }
        // Headers as Spotlight has them: the first result is the Top Hit, and each kind of result after it
        // gets its own header the first time it appears.
        var shown = Set<String>()
        for index in list.indices {
            let group: String
            switch list[index].kind {
            case .item: group = "Library"
            case .clip: group = "Clipboard"
            case .snippet: group = "Snippets"
            default: group = "Suggestions"
            }
            if index == 0 {
                list[index].section = "Top Hit"
            } else if shown.insert(group).inserted {
                list[index].section = group
            } else {
                list[index].section = nil
            }
        }
        return list
    }

    /// A row that adds the copied link or application to the library, when there is one to add.
    private func suggestion(section: String?) -> [QuickOpenResult] {
        guard let suggestion = store.suggestion(selection: selectedText) else { return [] }
        return [QuickOpenResult(kind: .addSuggestion(suggestion), id: "add-suggestion", section: section)]
    }

    /// Clipboard history rows, under a Clipboard header.
    private func clipboardResults(_ items: ArraySlice<ClipItem>) -> [QuickOpenResult] {
        var rows = items.map { QuickOpenResult(kind: .clip($0), id: "clip-\($0.id)") }
        if !rows.isEmpty { rows[0].section = "Clipboard" }
        return rows
    }

    func icon(for result: QuickOpenResult) -> NSImage {
        switch result.kind {
        case .addSuggestion: return symbol("plus.circle")
        case .clip(let item): return ClipboardLock.shared.icon(for: item)
        case .item(let node, _): return store.icon(for: node)
        case .openLink: return symbol("safari")
        case .snippet: return symbol("text.quote")
        case .addLink: return symbol("plus.circle")
        }
    }

    /// What dragging a row into another app drops: its picture, file, link, or text.
    func dragProvider(for result: QuickOpenResult) -> NSItemProvider {
        let provider = NSItemProvider()
        isDragging = true
        switch result.kind {
        case .clip(let item) where !ClipboardLock.shared.isHidden(item):
            if let image = item.image {
                provider.registerObject(image, visibility: .all)
            } else if let url = item.fileURLs.first {
                provider.registerObject(url as NSURL, visibility: .all)
            } else if let text = item.plainText {
                provider.registerObject(text as NSString, visibility: .all)
            }
        case .item(let node, _):
            if let url = node.shareURL { provider.registerObject(url as NSURL, visibility: .all) }
        case .openLink(let url), .addLink(let url):
            provider.registerObject(url as NSURL, visibility: .all)
        case .snippet(let snippet):
            provider.registerObject(snippet.text as NSString, visibility: .all)
        default:
            break
        }
        return provider
    }

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    /// Selects the row under the pointer, but only after the pointer actually moved. A list that scrolls under a
    /// still pointer, or a panel that opens under it, must not change the selection.
    func hover(_ id: String) {
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 3 else { return }
        lastMouse = mouse
        if selection != id {
            selectedByHover = true
            selection = id
        }
    }

    func resetSelection() {
        selectedByHover = false
        selection = results.first?.id
        showActions = false
    }

    func move(_ step: Int) {
        if showActions {
            actionSelection = min(max(actionSelection + step, 0), max(actions.count - 1, 0))
            return
        }
        selectedByHover = false
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap(ids.firstIndex(of:)) ?? 0
        selection = ids[min(max(current + step, 0), ids.count - 1)]
    }

    /// Selects the nth result, as Command-1 to Command-9 do in Spotlight.
    func select(index: Int) -> Bool {
        let list = results
        guard !showActions, list.indices.contains(index) else { return false }
        selection = list[index].id
        return true
    }

    var selected: QuickOpenResult? {
        results.first { $0.id == selection } ?? results.first
    }

    func toggleActions() {
        if showActions {
            showActions = false
        } else if selected?.hasActions == true {
            actionSelection = 0
            showActions = true
        }
    }

    /// Actions for the selected item.
    var actions: [QuickOpenAction] {
        selected.map(actions(for:)) ?? []
    }

    /// Actions for a result: open it, open it the other way, or copy what it points to.
    func actions(for result: QuickOpenResult) -> [QuickOpenAction] {
        if case .clip(let item) = result.kind { return clipActions(for: item) }
        if case .snippet(let snippet) = result.kind { return snippetActions(for: snippet) }
        if case .openLink(let url) = result.kind { return linkActions(for: url) }
        if case .addLink(let url) = result.kind { return linkActions(for: url) }
        guard let node = result.node else { return [] }
        var list = [QuickOpenAction(id: "open", title: "Open") { open(node) }]
        if let labels = node.modeLabels {
            let flipped = node.openNew == true ? labels.existing : labels.new
            list.append(QuickOpenAction(id: "flip", title: flipped) { open(node, forceNew: node.openNew != true) })
        }
        func copy(_ title: String, _ text: String) {
            list.append(QuickOpenAction(id: title, title: title) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            })
        }
        if let url = node.url {
            copy("Copy Link", url)
            copy("Copy Clean Link", TrackingParameters.clean(url))
        }
        if let command = node.command { copy("Copy Command", command) }
        if let path = node.appPath {
            copy("Copy Path", path)
            list.append(QuickOpenAction(id: "reveal", title: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        return list
    }

    /// A link typed into Quick Open: copy it without its tracking parameters.
    private func linkActions(for url: URL) -> [QuickOpenAction] {
        [QuickOpenAction(id: "copy-clean", title: "Copy Clean Link") { Self.copyText(TrackingParameters.clean(url.absoluteString)) }]
    }

    private func snippetActions(for snippet: Snippet) -> [QuickOpenAction] {
        [
            QuickOpenAction(id: "copy", title: "Copy") { Self.copyText(snippet.text) },
            QuickOpenAction(id: "edit", title: "Edit") { SnippetEditorWindow.show(snippet) },
        ]
    }

    /// Puts plain text on the clipboard. Clipboard history records it like any other copy.
    private static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func clipActions(for item: ClipItem) -> [QuickOpenAction] {
        let history = ClipboardHistory.shared
        // Every action that copies or shows the text goes through the lock. Pin and Delete reveal nothing.
        let lock = ClipboardLock.shared
        let verb = pastes ? "Paste" : "Copy"
        var list = [QuickOpenAction(id: "copy", title: verb) { [pastes] in
            lock.perform(item, for: .copy) {
                history.copy(item)
                if pastes { FrontApp.pasteSoon() }
            }
        }]
        if pastes {
            list.append(QuickOpenAction(id: "copy-only", title: "Copy") { lock.perform(item, for: .copy) { history.copy(item) } })
        }
        if item.plainText != nil {
            list.append(QuickOpenAction(id: "plain", title: "\(verb) as Plain Text") { [pastes] in
                lock.perform(item, for: .copy) {
                    history.copyPlainText(item)
                    if pastes { FrontApp.pasteSoon() }
                }
            })
        }
        if item.kind == .link, let link = item.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) {
            list.append(QuickOpenAction(id: "copy-clean", title: "Copy Clean Link") { lock.perform(item, for: .copy) { Self.copyText(TrackingParameters.clean(link)) } })
        }
        list.append(QuickOpenAction(id: "quick-look", title: "Quick Look") { lock.perform(item, for: .show) { ClipPreview.shared.show(item) } })
        list.append(QuickOpenAction(id: "pin", title: item.pinned ? "Unpin" : "Pin") { history.togglePin(item) })
        if item.libraryNode != nil {
            list.append(QuickOpenAction(id: "add", title: "Add to Library") { [store] in
                lock.perform(item, for: .show) { store.addToLibrary(item) }
            })
        }
        list.append(QuickOpenAction(id: "delete", title: "Delete") { history.remove(item) })
        return list
    }

    /// Runs the chosen action or result. `flip` does the opposite of the item's open setting.
    func activate(flip: Bool) {
        if showActions {
            let list = actions
            if list.indices.contains(actionSelection) { list[actionSelection].run() }
            return
        }
        guard let result = selected else { return }
        switch result.kind {
        case .snippet(let snippet):
            Self.copyText(snippet.text)
        case .addSuggestion(let suggestion):
            store.add(suggestion)
        case .clip(let item):
            ClipboardLock.shared.perform(item, for: .copy) { [pastes] in
                ClipboardHistory.shared.copy(item)
                if pastes { FrontApp.pasteSoon() }
            }
        case .item(let node, _):
            open(node, forceNew: flip ? node.openNew != true : nil)
        case .openLink(let url):
            NSWorkspace.shared.open(url)
        case .addLink(let url):
            store.perform("Add Bookmark") {
                $0.append(LibraryItem(name: url.host ?? url.absoluteString, url: url.absoluteString), to: nil)
            }
        }
    }
}
