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
    private var nodesObserver: AnyCancellable?
    private var snippetsObserver: AnyCancellable?
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
    /// The id of the action whose submenu, such as Copy as…, is listed in place of the actions. Nil otherwise.
    @Published var actionGroup: String?
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
        // Any change to the library drops the index and recomputes the rows, the way a clipboard change does. An open panel
        // is usually short-lived, but iCloud sync or a link check can write to the library while it is open.
        nodesObserver = store.$contents.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.index = nil
            // @Published sends before the new value is stored, so rebuilding here would read the library as it was.
            // The next turn of the run loop is after the store holds the change.
            DispatchQueue.main.async { [weak self] in self?.libraryChanged() }
        }
        // Snippets are part of the search index, so a change to them rebuilds it too.
        snippetsObserver = SnippetStore.shared.$snippets.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.index = nil
            DispatchQueue.main.async { [weak self] in self?.libraryChanged() }
        }
        results = computeResults()
        // A copied GIF finishing its download updates the open panel.
        // A copy added or removed changes the clip rows, so the results are recomputed too.
        historyObserver = ClipboardHistory.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send()
            self?.historyChanged()
            self?.refreshPreview()
        }
        // Unlocking or locking a pinned item changes what the rows and the preview show.
        lockObserver = ClipboardLock.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send()
            self?.refreshPreview()
        }
    }

    /// Space previews the selected clip in Quick Look, or closes the preview if it is open. Returns false, so Space
    /// types a space, when the search has text, or when there is nothing to preview.
    /// A locked pinned item asks for authentication first, and Space is used up by that.
    func togglePreview() -> Bool {
        guard Self.spaceTogglesPreview(query: query, showActions: showActions, selectionIsClip: selected?.clip != nil),
              let item = selected?.clip else { return false }
        if ClipboardLock.shared.isHidden(item) {
            ClipboardLock.shared.perform(item, for: .show) { ClipPreview.shared.toggle(item) }
            return true
        }
        return ClipPreview.shared.toggle(item)
    }

    /// Space previews only when the search is empty, so a multi-word search can contain a space. With text in the
    /// search, Space always types a space.
    nonisolated static func spaceTogglesPreview(query: String, showActions: Bool, selectionIsClip: Bool) -> Bool {
        !showActions && query.isEmpty && selectionIsClip
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

    /// Recomputes the results after the clipboard history changed. The selection stays on its row when that row is still
    /// listed, and moves to the first result when it is gone.
    private func historyChanged() {
        results = computeResults()
        if let selection, !results.contains(where: { $0.id == selection }) {
            resetSelection()
        }
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

    /// Puts the rows back after the library changed under an open panel, so a removed item loses its row without a
    /// keystroke and an edited one shows what it is now.
    private func libraryChanged() {
        results = computeResults()
        if let selection, !results.contains(where: { $0.id == selection }) { resetSelection() }
    }

    /// The node a row stands for, taken from the library as it is now rather than the copy the row was built from. An
    /// item that has been removed or edited since the row was made is the library's version or nothing at all.
    func currentNode(_ result: QuickOpenResult) -> LibraryItem? {
        guard let id = result.node?.id else { return nil }
        return store.nodes.node(withID: id)
    }

    /// What the panel runs for the selected row. A library row is resolved against the library as it is now, so an edited
    /// item opens its current address, and an item that has been removed runs nothing at all. A row that is not a
    /// library item is used as it is.
    func activatableKind(for selection: String?) -> QuickOpenResult.Kind? {
        guard let selection, let result = results.first(where: { $0.id == selection }) else { return nil }
        guard case .item(_, let folder) = result.kind else { return result.kind }
        guard let node = result.node, let current = store.nodes.node(withID: node.id) else { return nil }
        return .item(current, folder: folder)
    }

    private func computeResults() -> [QuickOpenResult] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let history = ClipboardHistory.shared
        // "from <app>" shows only the clips copied while that app was in front, so the library is not searched.
        let source = text.isEmpty ? nil : SourceFilter.parse(text, apps: history.sourceApps)
        var list = source == nil ? searchIndex().search(text, counts: store.openCounts) : []
        guard !text.isEmpty else {
            // The same Frequently Used section the menu has, first. Its ids differ from the library rows' ids,
            // so an item can sit in both without clashing.
            var frequent = store.frequent.map { QuickOpenResult(kind: .item($0, folder: ""), id: "\($0.id.uuidString)#frequent") }
            if !frequent.isEmpty { frequent[0].section = "Frequently Used" }
            return suggestion(section: "Suggested") + frequent + list
                + clipboardResults(ClipboardHistory.shared.displayOrder.prefix(5))
        }
        if let source {
            list += clipboardResults(history.search(source.rest, from: source.app))
        } else {
            list += clipboardResults(history.search(text).prefix(8))
            // Typing "add" or part of "add to library" also offers the copied link or application.
            if text.count >= 2, "add to library".contains(text.lowercased()) {
                list = suggestion(section: nil) + list
            }
            if let link = QuickOpenResult.link(from: text) {
                list.insert(QuickOpenResult(kind: .openLink(link), id: "open"), at: 0)
                list.append(QuickOpenResult(kind: .addLink(link), id: "add"))
            }
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
    private func clipboardResults<Items: Sequence>(_ items: Items) -> [QuickOpenResult] where Items.Element == ClipItem {
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

    /// What dragging a row into another app carries: its picture, file, link, or text.
    func dragPayload(for result: QuickOpenResult) -> QuickOpenDrag {
        let hidden = result.clip.map { ClipboardLock.shared.isHidden($0) } ?? false
        return QuickOpenDrag.payload(for: result.kind, clipHidden: hidden)
    }

    private func symbol(_ name: String) -> NSImage {
        symbolImage(name) ?? NSImage()
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
        actionGroup = nil
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
            actionGroup = nil
        } else if selected?.hasActions == true {
            actionSelection = 0
            showActions = true
        }
    }

    /// Actions for the selected item, or the submenu that is open.
    var actions: [QuickOpenAction] {
        guard let result = selected else { return [] }
        let list = actions(for: result)
        if let actionGroup, let group = list.first(where: { $0.id == actionGroup }) { return group.children }
        return list
    }

    /// True when Return would open a submenu rather than run an action.
    var selectedActionOpensGroup: Bool {
        guard showActions, actionGroup == nil, actions.indices.contains(actionSelection) else { return false }
        return !actions[actionSelection].children.isEmpty
    }

    /// Lists the submenu of an action in place of the actions. Escape goes back.
    func openGroup(_ action: QuickOpenAction) {
        actionGroup = action.id
        actionSelection = 0
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
            if !node.isTemplate {
                list.append(QuickOpenAction(id: "markdown", title: String(localized: "Copy as Markdown Link", bundle: L10n.bundle)) {
                    MarkdownLink.copy(title: node.name, url: url, to: .general)
                })
            }
        }
        if let command = node.command { copy("Copy Command", command) }
        if let path = node.appPath {
            copy("Copy Path", path)
            list.append(QuickOpenAction(id: "reveal", title: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        if node.canReadLater {
            list += readingListActions(for: node)
        }
        return list
    }

    /// The Reading List actions for a bookmark: add it, or mark it read or unread, and remove it when it is listed.
    private func readingListActions(for node: LibraryItem) -> [QuickOpenAction] {
        let store = self.store
        let id = node.id
        func action(_ change: ReadingList.Action) -> QuickOpenAction {
            QuickOpenAction(id: "reading-\(change)", title: change.title) { store.changeReadingList([id], change) }
        }
        switch node.readLater {
        case nil: return [action(.add)]
        case .unread?: return [action(.markRead), action(.remove)]
        case .read?: return [action(.markUnread), action(.remove)]
        case .unknown?: return [action(.markRead), action(.remove)]
        }
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
        if item.kind == .text, let text = item.plainText {
            let transforms = ClipTransform.allCases.map { transform in
                QuickOpenAction(id: "\(transform)", title: transform.title) { [pastes] in
                    lock.perform(item, for: .copy) {
                        history.copyText(transform.apply(text))
                        if pastes { FrontApp.pasteSoon() }
                    }
                }
            }
            list.append(QuickOpenAction(id: "copy-as", title: String(localized: "Copy as…", bundle: L10n.bundle),
                                        children: transforms) {})
            list += smartActions(for: item, text: text)
        }
        if item.kind == .link, let link = item.link {
            list.append(QuickOpenAction(id: "markdown", title: String(localized: "Copy as Markdown Link", bundle: L10n.bundle)) { [pastes] in
                lock.perform(item, for: .copy) {
                    MarkdownLink.copy(title: link.host ?? link.absoluteString, url: link.absoluteString, to: .general)
                    if pastes { FrontApp.pasteSoon() }
                }
            })
        }
        list.append(QuickOpenAction(id: "quick-look", title: "Quick Look") { lock.perform(item, for: .show) { ClipPreview.shared.show(item) } })
        list.append(QuickOpenAction(id: "pin", title: item.pinned ? "Unpin" : "Pin") {
            // Unpinning a locked item reveals its text, so it needs the same authentication as showing it.
            ClipboardLock.shared.perform(item, for: .show) { history.togglePin(item) }
        })
        list.append(QuickOpenAction(id: "queue", title: String(localized: "Add to Paste Queue", bundle: L10n.bundle)) {
            history.enqueue(item)
        })
        if item.libraryNode != nil {
            list.append(QuickOpenAction(id: "add", title: "Add to Library") { [store] in
                lock.perform(item, for: .show) { store.addToLibrary(item) }
            })
        }
        list.append(QuickOpenAction(id: "delete", title: "Delete") { history.remove(item) })
        return list
    }

    /// Actions for an address, a phone number, or a date in a text clip. Each appears only when the text has one.
    private func smartActions(for item: ClipItem, text: String) -> [QuickOpenAction] {
        let history = ClipboardHistory.shared
        let lock = ClipboardLock.shared
        let found = SmartText.detect(text)
        var list: [QuickOpenAction] = []
        if let address = found.address, let url = SmartText.mapsURL(for: address) {
            list.append(QuickOpenAction(id: "maps", title: String(localized: "Open in Maps", bundle: L10n.bundle),
                                        icon: "mappin.and.ellipse") {
                lock.perform(item, for: .show) { NSWorkspace.shared.open(url) }
            })
        }
        if let phone = found.phone {
            let digits = SmartText.phoneDigits(phone)
            list.append(QuickOpenAction(id: "phone", title: String(localized: "Copy Phone Number", bundle: L10n.bundle),
                                        icon: "phone") { [pastes] in
                lock.perform(item, for: .copy) {
                    history.copyText(digits)
                    if pastes { FrontApp.pasteSoon() }
                }
            })
        }
        if let date = found.date {
            list.append(QuickOpenAction(id: "calendar", title: String(localized: "Add to Calendar", bundle: L10n.bundle),
                                        icon: "calendar.badge.plus") {
                lock.perform(item, for: .show) { SmartText.openInCalendar(text: text, date: date) }
            })
        }
        return list
    }

    /// Runs the chosen action or result. `flip` does the opposite of the item's open setting.
    func activate(flip: Bool) {
        if showActions {
            let list = actions
            guard list.indices.contains(actionSelection) else { return }
            let action = list[actionSelection]
            if action.children.isEmpty { action.run() } else { openGroup(action) }
            return
        }
        guard let kind = activatableKind(for: selected?.id) else { return }
        switch kind {
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
            let node = LibraryItem(name: url.host ?? url.absoluteString, url: url.absoluteString)
            store.perform("Add Bookmark") { $0.append(node, to: nil) }
            SmartTitle.nameFromPage(node.id, url: url)
        }
    }
}
