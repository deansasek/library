import SwiftUI

/// Runs `command` in a new Terminal window, then leaves a shell open.
/// A throwaway `.command` file avoids the Automation permission that AppleScript needs.
func runInTerminal(_ command: String) {
    removeStaleCommandFiles()
    guard let file = writeCommandFile(commandScript(command), in: FileManager.default.temporaryDirectory) else { return }
    // A file that Terminal does not open is deleted now, since the script never runs to delete itself.
    guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
        try? FileManager.default.removeItem(at: file)
        return
    }
    NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        if error != nil {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// The script Terminal runs. It deletes itself first, then runs the command, then leaves a shell open.
func commandScript(_ command: String) -> String {
    "#!/bin/zsh -il\nrm -f -- \"$0\"\n\(command)\nexec zsh -il\n"
}

/// Writes the script to a new executable file in `folder` and returns its address. The mode is set when the file is
/// created, so it is never readable or runnable by anyone else, not even briefly. Nil when it could not be written.
func writeCommandFile(_ script: String, in folder: URL) -> URL? {
    let file = folder.appendingPathComponent("library-\(UUID().uuidString).command")
    let created = FileManager.default.createFile(atPath: file.path, contents: Data(script.utf8),
                                                 attributes: [.posixPermissions: 0o700])
    return created ? file : nil
}

/// Deletes `library-*.command` files in the temporary folder that are over an hour old. The script deletes
/// itself when Terminal runs it, so any left behind were never run. Called at launch and each time a new one is written.
func removeStaleCommandFiles(now: Date = .now) {
    let folder = FileManager.default.temporaryDirectory
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { return }
    let entries = urls.compactMap { url -> (name: String, modified: Date)? in
        guard let modified = (try? url.resourceValues(forKeys: keys))?.contentModificationDate else { return nil }
        return (url.lastPathComponent, modified)
    }
    let stale = Set(staleCommandFiles(among: entries, now: now))
    for url in urls where stale.contains(url.lastPathComponent) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The names, among `files`, of this app's `.command` files that are more than an hour old at `now`.
func staleCommandFiles(among files: [(name: String, modified: Date)], now: Date) -> [String] {
    files.filter { file in
        isCommandFileName(file.name) && now.timeIntervalSince(file.modified) > 3600
    }.map(\.name)
}

/// True for the exact name this app writes, `library-<UUID>.command`. Another file that only starts and ends the same
/// way is not this app's, so it is left alone.
func isCommandFileName(_ name: String) -> Bool {
    let prefix = "library-", suffix = ".command"
    guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return false }
    let middle = name.dropFirst(prefix.count).dropLast(suffix.count)
    return UUID(uuidString: String(middle)) != nil
}

/// Splits a command line into arguments. Single or double quotes group words.
func splitArguments(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    var started = false
    for char in line {
        if let open = quote {
            if char == open { quote = nil } else { current.append(char) }
        } else if char == "\"" || char == "'" {
            quote = char
            started = true
        } else if char.isWhitespace {
            if started { result.append(current) }
            current = ""
            started = false
        } else {
            current.append(char)
            started = true
        }
    }
    if started { result.append(current) }
    return result
}

/// The prompt text for a template field. A bare `{}` uses the item's prompt label, and a named field without a label
/// uses its name.
private func fieldLabel(_ field: TemplateField, node: LibraryItem) -> String {
    if let label = field.label { return label }
    if field.name.isEmpty { return node.promptLabel ?? "Value" }
    return field.name.prefix(1).uppercased() + field.name.dropFirst()
}

/// Asks for the values that fill a URL template, one field per placeholder, in one sheet. Returns the values by
/// placeholder name, or nil when cancelled or when a value is empty. Return opens, and Escape cancels.
@MainActor
private func promptValues(for node: LibraryItem) -> [String: String]? {
    let fields = node.placeholders
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = node.name
    let inputs = fields.map { field -> NSTextField in
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = fieldLabel(field, node: node)
        return input
    }
    if inputs.count == 1 {
        alert.informativeText = fieldLabel(fields[0], node: node)
        alert.accessoryView = inputs[0]
        alert.window.initialFirstResponder = inputs[0]
    } else {
        alert.informativeText = String(localized: "Fill in each value.", bundle: L10n.bundle)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for (field, input) in zip(fields, inputs) {
            stack.addArrangedSubview(NSTextField(labelWithString: fieldLabel(field, node: node)))
            input.translatesAutoresizingMaskIntoConstraints = false
            input.widthAnchor.constraint(equalToConstant: 260).isActive = true
            stack.addArrangedSubview(input)
        }
        stack.layoutSubtreeIfNeeded()
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = inputs.first
        alert.window.recalculateKeyViewLoop()
    }
    alert.addButton(withTitle: String(localized: "Open", bundle: L10n.bundle))
    alert.addButton(withTitle: String(localized: "Cancel", bundle: L10n.bundle))
    alert.buttons[1].keyEquivalent = "\u{1b}"
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    var values: [String: String] = [:]
    for (field, input) in zip(fields, inputs) {
        let value = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        values[field.name] = value
    }
    return values
}

/// Opens each item of a folder in turn, after confirming when there are many. Items are spaced about 150 ms apart,
/// so browsers and apps are not flooded. The selection is `openAllSelection(in:)`.
@MainActor
func openAll(_ nodes: [LibraryItem]) {
    let items = openAllSelection(in: nodes)
    guard !items.isEmpty else { return }
    if needsOpenAllConfirmation(items.count) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "Open %lld items?", bundle: L10n.bundle), items.count)
        alert.informativeText = String(localized: "Library opens them one after another.", bundle: L10n.bundle)
        alert.addButton(withTitle: String(localized: "Cancel", bundle: L10n.bundle))
        alert.addButton(withTitle: String(localized: "Open", bundle: L10n.bundle))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    Task { @MainActor in
        for (index, node) in items.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(150)) }
            open(node)
        }
    }
}

/// Looked up once, since rows ask for it on every redraw. A browser installed later shows after a restart.
private let browserList: [(id: String, name: String)] = {
    let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
    return urls.compactMap { url in
        Bundle(url: url)?.bundleIdentifier.map { ($0, appName(at: url.path)) }
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}()

/// The browsers installed on this Mac: the apps that can open web links.
func installedBrowsers() -> [(id: String, name: String)] { browserList }

/// New-window launch flags for browsers that accept them. `browser` is the app to use, or the default browser.
private func openInNewWindow(_ link: URL, in browser: URL?) {
    guard let app = browser ?? NSWorkspace.shared.urlForApplication(toOpen: link) else {
        NSWorkspace.shared.open(link)
        return
    }
    let id = Bundle(url: app)?.bundleIdentifier ?? ""
    guard let flag = newWindowFlag(bundleID: id) else {
        // A browser with no new-window flag still gets the link, so it is not sent to the default browser.
        NSWorkspace.shared.open([link], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return
    }
    // A second launch hands the URL to the running browser and exits.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [flag, link.absoluteString]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: app, configuration: configuration)
}

/// The launch flag that opens a new window in a browser, by its bundle identifier. Nil for a browser with no such flag.
func newWindowFlag(bundleID: String) -> String? {
    let id = bundleID.lowercased()
    let chromium = ["chrome", "chromium", "edgemac", "brave", "vivaldi", "thebrowser", "opera"]
    if id.contains("firefox") { return "-new-window" }
    if chromium.contains(where: id.contains) { return "--new-window" }
    return nil
}

/// Asks before a terminal command runs, when the Settings option is on. Cancel is the default button.
@MainActor
private func confirmCommand(_ node: LibraryItem, _ command: String) -> Bool {
    guard UserDefaults.standard.bool(forKey: "confirmTerminalCommands") else { return true }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = String(format: String(localized: "Run “%@” in Terminal?", bundle: L10n.bundle), node.name)
    alert.informativeText = command
    alert.addButton(withTitle: String(localized: "Cancel", bundle: L10n.bundle))
    alert.addButton(withTitle: String(localized: "Run", bundle: L10n.bundle))
    return alert.runModal() == .alertSecondButtonReturn
}

/// Whether a `library://open` link must ask before it opens the item. An app with arguments asks, and so does a
/// template that the link fills with a value. Bookmarks and plain apps open without a prompt.
func linkOpenNeedsConfirmation(_ node: LibraryItem, value: String?) -> Bool {
    if node.command != nil { return false }
    if node.appPath != nil { return !splitArguments(node.arguments ?? "").isEmpty }
    return node.isTemplate && value != nil
}

/// Asks before a web page's link opens an app with arguments or fills a template. Cancel is the default button.
@MainActor
func confirmLinkOpen(_ node: LibraryItem, value: String?) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = String(format: String(localized: "Open “%@” from a link?", bundle: L10n.bundle), node.name)
    if node.appPath != nil {
        alert.informativeText = String(format: String(localized: "The link opens this app with the arguments: %@", bundle: L10n.bundle), node.arguments ?? "")
    } else {
        alert.informativeText = String(format: String(localized: "The link fills this address with: %@", bundle: L10n.bundle), value ?? "")
    }
    alert.addButton(withTitle: String(localized: "Cancel", bundle: L10n.bundle))
    alert.addButton(withTitle: String(localized: "Open", bundle: L10n.bundle))
    return alert.runModal() == .alertSecondButtonReturn
}

/// Asks before an app that a Shortcut or another app added through an intent opens. Cancel is the default button.
@MainActor
private func confirmIntentApp(_ node: LibraryItem) -> Bool {
    guard IntentLogic.needsLaunchConfirmation(node) else { return true }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = String(format: String(localized: "Open “%@”?", bundle: L10n.bundle), node.name)
    alert.informativeText = String(localized: "A Shortcut or another app added this application to Library. Open it only if you expect it.", bundle: L10n.bundle)
    alert.addButton(withTitle: String(localized: "Cancel", bundle: L10n.bundle))
    alert.addButton(withTitle: String(localized: "Open", bundle: L10n.bundle))
    return alert.runModal() == .alertSecondButtonReturn
}

/// Opens a bookmark in the browser, or runs a terminal command. Opens an app,
/// or brings it to the front when it already runs. `forceNew` overrides the item's own setting.
/// `value` fills a URL template with a single field without asking. Templates with several fields always ask.
@MainActor
func open(_ node: LibraryItem, forceNew: Bool? = nil, value: String? = nil) {
    let openNew = forceNew ?? (node.openNew == true)
    if let command = node.command {
        guard confirmCommand(node, command) else { return }
        LibraryStore.shared.recordOpen(node.id)
        runInTerminal(command)
    } else if let path = node.appPath {
        guard confirmIntentApp(node) else { return }
        LibraryStore.shared.recordOpen(node.id)
        let configuration = NSWorkspace.OpenConfiguration()
        let arguments = splitArguments(node.arguments ?? "")
        configuration.arguments = arguments
        // A running app ignores arguments unless it starts a new instance.
        configuration.createsNewApplicationInstance = openNew || !arguments.isEmpty
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
    } else if node.url != nil {
        var link = node.link
        if node.isTemplate {
            let values: [String: String]?
            if let value, node.placeholders.count == 1 {
                values = [node.placeholders[0].name: value]
            } else {
                values = promptValues(for: node)
            }
            guard let values, let filled = node.link(values: values) else { return }
            link = filled
        }
        if let link {
            LibraryStore.shared.recordOpen(node.id)
            // A browser that was removed falls back to the default browser.
            let browser = node.browser.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            if openNew {
                openInNewWindow(link, in: browser)
            } else if let browser {
                NSWorkspace.shared.open([link], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(link)
            }
        }
    }
}
