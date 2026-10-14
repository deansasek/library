import Combine
import SwiftUI

@MainActor
final class QuickOpenModel: ObservableObject {
    let store: LibraryStore
    /// Searched when the text changes, not on every redraw.
    @Published var query = "" {
        didSet { results = computeResults() }
    }
    @Published private(set) var results: [QuickOpenResult] = []
    @Published var selection: String? {
        didSet { refreshPreview() }
    }
    private var animatedImages: [UUID: NSImage] = [:]

    /// The playing image for a copied GIF, decoded once and kept while the panel is open.
    func animatedImage(for item: ClipItem) -> NSImage? {
        // The row holds a copy from when the list was built. A GIF may have finished downloading since.
        let item = ClipboardHistory.shared.items.first { $0.id == item.id } ?? item
        guard item.isAnimated else { return nil }
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

    /// The text selected in the app that was in front when Quick Open opened. It can suggest adding a link.
    private let selectedText: String?

    /// True when a text field had the keyboard when Quick Open opened. Choosing a clipboard item pastes it then.
    private let pastes: Bool

    init(store: LibraryStore, selectedText: String?, pastes: Bool) {
        self.store = store
        self.selectedText = selectedText
        self.pastes = pastes
        results = computeResults()
        // A copied GIF finishing its download updates the open panel.
        historyObserver = ClipboardHistory.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.objectWillChange.send()
            self?.refreshPreview()
        }
    }

    private func refreshPreview() {
        previewImage = selected?.clip.flatMap { animatedImage(for: $0) ?? $0.image }
    }

    private func computeResults() -> [QuickOpenResult] {
        let text = query.trimmingCharacters(in: .whitespaces)
        var list = QuickOpenResult.search(text, in: store.nodes, counts: store.openCounts)
        guard !text.isEmpty else {
            // The same Frequently Used section the menu has, first. Its ids differ from the library rows' ids,
            // so an item can sit in both without clashing.
            var frequent = store.frequent.map { QuickOpenResult(kind: .item($0, folder: ""), id: "\($0.id.uuidString)#frequent") }
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
        list.append(QuickOpenResult(kind: .webSearch(text), id: "web"))
        if let answer = QuickAnswers.answer(for: text) {
            list.insert(QuickOpenResult(kind: .answer(value: answer.value, detail: answer.detail), id: "answer"), at: 0)
        }
        // Headers as Spotlight has them: the first result is the Top Hit, and each kind of result after it
        // gets its own header the first time it appears.
        var shown = Set<String>()
        for index in list.indices {
            let group: String
            switch list[index].kind {
            case .item: group = "Library"
            case .clip: group = "Clipboard"
            case .answer: group = "Answer"
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
        case .answer: return symbol("equal.circle")
        case .addSuggestion: return symbol("plus.circle")
        case .clip(let item): return item.icon
        case .item(let node, _): return store.icon(for: node)
        case .openLink: return symbol("safari")
        case .addLink: return symbol("plus.circle")
        case .webSearch: return symbol("magnifyingglass")
        }
    }

    /// What dragging a row into another app drops: its picture, file, link, or text.
    func dragProvider(for result: QuickOpenResult) -> NSItemProvider {
        let provider = NSItemProvider()
        isDragging = true
        switch result.kind {
        case .clip(let item):
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
        case .answer(let value, _):
            provider.registerObject(value as NSString, visibility: .all)
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
        if let url = node.url { copy("Copy Link", url) }
        if let command = node.command { copy("Copy Command", command) }
        if let path = node.appPath {
            copy("Copy Path", path)
            list.append(QuickOpenAction(id: "reveal", title: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        return list
    }

    private func clipActions(for item: ClipItem) -> [QuickOpenAction] {
        let history = ClipboardHistory.shared
        let verb = pastes ? "Paste" : "Copy"
        var list = [QuickOpenAction(id: "copy", title: verb) { [pastes] in
            history.copy(item)
            if pastes { FrontApp.pasteSoon() }
        }]
        if pastes {
            list.append(QuickOpenAction(id: "copy-only", title: "Copy") { history.copy(item) })
        }
        if item.plainText != nil {
            list.append(QuickOpenAction(id: "plain", title: "\(verb) as Plain Text") { [pastes] in
                history.copyPlainText(item)
                if pastes { FrontApp.pasteSoon() }
            })
        }
        list.append(QuickOpenAction(id: "pin", title: item.pinned ? "Unpin" : "Pin") { history.togglePin(item) })
        if item.libraryNode != nil {
            list.append(QuickOpenAction(id: "add", title: "Add to Library") { [store] in store.addToLibrary(item) })
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
        case .answer(let value, _):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case .addSuggestion(let suggestion):
            store.add(suggestion)
        case .clip(let item):
            ClipboardHistory.shared.copy(item)
            if pastes { FrontApp.pasteSoon() }
        case .item(let node, _):
            open(node, forceNew: flip ? node.openNew != true : nil)
        case .openLink(let url):
            NSWorkspace.shared.open(url)
        case .addLink(let url):
            store.perform("Add Bookmark") {
                $0.append(LibraryItem(name: url.host ?? url.absoluteString, url: url.absoluteString), to: nil)
            }
        case .webSearch(let query):
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
