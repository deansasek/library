import AppIntents
import UniformTypeIdentifiers

/// A failure a Shortcut shows as its message.
struct LibraryIntentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The library item with `id`, if it still exists and can be opened.
@MainActor
private func launchableNode(_ entity: LibraryItemEntity) throws -> LibraryItem {
    guard let uuid = UUID(uuidString: entity.id), let node = LibraryStore.shared.nodes.node(withID: uuid),
          IntentLogic.isLaunchable(node) else {
        throw LibraryIntentError("“\(entity.name)” is no longer in Library.")
    }
    return node
}

struct OpenBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Library Item"
    static let description = IntentDescription("Opens a bookmark or application from Library.")

    @Parameter(title: "Item")
    var item: LibraryItemEntity

    @Parameter(title: "Value", description: "Fills the {} placeholder of a URL template. Asks when left empty.")
    var value: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let node = try launchableNode(item)
        open(node, value: value)
        return .result(dialog: "Opened \(node.name).")
    }
}

struct SearchLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Library"
    static let description = IntentDescription("Finds bookmarks and applications in Library that match the text.")

    @Parameter(title: "Search")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[LibraryItemEntity]> {
        let store = LibraryStore.shared
        let found = IntentLogic.launchables(matching: query, in: store.nodes, counts: store.openCounts)
            .map(LibraryItemEntity.init)
        return .result(value: found)
    }
}

struct AddBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Bookmark to Library"
    static let description = IntentDescription("Adds a web link to Library as a bookmark.")

    @Parameter(title: "Web Link")
    var link: URL

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let node = IntentLogic.bookmark(from: link.absoluteString) else {
            throw LibraryIntentError("That is not a web link.")
        }
        LibraryStore.shared.perform("Add Bookmark") { $0.append(node, to: nil) }
        // Same as adding from the menus: the name comes from the page when the setting is on.
        if let page = node.link { SmartTitle.nameFromPage(node.id, url: page) }
        return .result(dialog: "Added \(node.name) to Library.")
    }
}

struct AddAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Application to Library"
    static let description = IntentDescription("Adds an application to Library.")

    @Parameter(title: "Application", supportedContentTypes: [.applicationBundle])
    var app: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let path = app.fileURL?.path, var node = IntentLogic.app(atPath: path) else {
            throw LibraryIntentError("Choose an application (.app) file.")
        }
        // An app outside /Applications and ~/Applications is added only after the person confirms. A declined dialog throws.
        if !IntentLogic.isStandardApplication(atPath: path) {
            try await requestConfirmation(dialog: IntentDialog(stringLiteral: IntentLogic.addConfirmation(for: node)))
        }
        // Launching it asks again, so a Shortcut cannot start an app that it added without the person seeing it.
        node.addedByIntent = true
        LibraryStore.shared.perform("Add Application") { $0.append(node, to: nil) }
        return .result(dialog: "Added \(node.name) to Library.")
    }
}

struct FrequentlyUsedIntent: AppIntent {
    static let title: LocalizedStringResource = "Frequently Used Library Items"
    static let description = IntentDescription("Returns the bookmarks and applications you open most often.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[LibraryItemEntity]> {
        let found = LibraryStore.shared.frequent.filter(IntentLogic.isLaunchable).map(LibraryItemEntity.init)
        return .result(value: found)
    }
}

struct OpenClipboardLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clipboard Link"
    static let description = IntentDescription("Opens the web link on the clipboard in the browser.")

    @MainActor
    func perform() async throws -> some IntentResult {
        LibraryStore.shared.openClipboardLink()
        return .result()
    }
}

struct PasteLatestClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Latest Clip"
    static let description = IntentDescription("Copies the most recent clipboard history item back to the clipboard. It does not paste into other apps.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // A locked pinned item is never copied here, since a shortcut cannot ask for Touch ID or the password.
        guard let item = ClipboardHistory.shared.items.first(where: { !ClipboardLock.shared.isHidden($0) }) else {
            throw LibraryIntentError("The clipboard history is empty.")
        }
        // A file that was moved or deleted is not copied, so the clip is not on the clipboard and the shortcut must
        // not say it was.
        guard ClipboardHistory.shared.copy(item) else {
            throw LibraryIntentError("The latest clip’s file is no longer there.")
        }
        return .result(dialog: "Copied the latest clip.")
    }
}

struct SearchClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Clipboard History"
    static let description = IntentDescription("Returns the text of clipboard history items that contain every word of the search.")

    @Parameter(title: "Search")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let texts = ClipboardHistory.shared.search(query)
            .prefix(20)
            .map { $0.plainText ?? $0.title }
        return .result(value: Array(texts))
    }
}

struct ShowQuickOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Quick Open"
    static let description = IntentDescription("Opens Library's Quick Open search.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LibraryStore.shared.showQuickOpen()
        return .result()
    }
}

struct ShowMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Library Menu"
    static let description = IntentDescription("Opens Library's bookmarks menu.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LibraryStore.shared.showMenu()
        return .result()
    }
}

struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Terminal Command"
    static let description = IntentDescription("Runs a terminal command from Library in a new Terminal window. Asks for confirmation every time.")

    @Parameter(title: "Command")
    var command: LibraryCommandEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Nothing runs until the person confirms. A declined dialog throws, which stops the Shortcut here.
        let first = try resolve()
        try await requestConfirmation(dialog: IntentDialog(stringLiteral: IntentLogic.confirmation(for: first)))
        // The library may have changed while the dialog was open, so the command is looked up again.
        let current = try resolve()
        guard current.command == first.command else {
            throw LibraryIntentError("The command changed while it was waiting for confirmation. Nothing ran.")
        }
        // The question above is the only one. The terminal runner is called directly, so the Settings option does not
        // add a second dialog on top of the Shortcuts confirmation.
        guard let text = current.command else {
            throw LibraryIntentError("“\(command.name)” is no longer a command in Library.")
        }
        LibraryStore.shared.recordOpen(current.id)
        runInTerminal(text)
        return .result(dialog: "Started \(current.name) in Terminal.")
    }

    @MainActor
    private func resolve() throws -> LibraryItem {
        guard let uuid = UUID(uuidString: command.id), let node = LibraryStore.shared.nodes.node(withID: uuid),
              IntentLogic.canRunCommand(node) else {
            throw LibraryIntentError("“\(command.name)” is no longer a command in Library.")
        }
        return node
    }
}
