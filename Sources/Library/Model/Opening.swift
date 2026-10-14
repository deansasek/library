import SwiftUI

/// Runs `command` in a new Terminal window, then leaves a shell open.
/// A throwaway `.command` file avoids the Automation permission that AppleScript needs.
private func runInTerminal(_ command: String) {
    removeStaleCommandFiles()
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("library-\(UUID().uuidString).command")
    let script = "#!/bin/zsh -il\nrm -f -- \"$0\"\n\(command)\nexec zsh -il\n"
    guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil,
          (try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)) != nil,
          let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    else { return }
    NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
}

/// Deletes `library-*.command` files in the temporary folder that are over an hour old. The script deletes
/// itself when Terminal runs it, so any left behind were never run. Called each time a new one is written.
private func removeStaleCommandFiles(now: Date = .now) {
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
        file.name.hasPrefix("library-") && file.name.hasSuffix(".command") && now.timeIntervalSince(file.modified) > 3600
    }.map(\.name)
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

/// Asks for the value that fills a URL template. Nil when cancelled or empty.
@MainActor
private func promptValue(for node: LibraryItem) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = node.name
    alert.informativeText = node.promptLabel ?? "Value"
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = node.promptLabel ?? "Value"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    alert.addButton(withTitle: "Open")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let value = field.stringValue.trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : value
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
    guard let app = browser ?? NSWorkspace.shared.urlForApplication(toOpen: link),
          let id = Bundle(url: app)?.bundleIdentifier?.lowercased() else {
        NSWorkspace.shared.open(link)
        return
    }
    let chromium = ["chrome", "chromium", "edgemac", "brave", "vivaldi", "thebrowser", "opera"]
    let flag: String
    if id.contains("firefox") {
        flag = "-new-window"
    } else if chromium.contains(where: id.contains) {
        flag = "--new-window"
    } else {
        NSWorkspace.shared.open(link)
        return
    }
    // A second launch hands the URL to the running browser and exits.
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [flag, link.absoluteString]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: app, configuration: configuration)
}

/// Opens a bookmark in the browser, or runs a terminal command. Opens an app,
/// or brings it to the front when it already runs. `forceNew` overrides the item's own setting.
/// `value` fills a URL template without asking.
@MainActor
func open(_ node: LibraryItem, forceNew: Bool? = nil, value: String? = nil) {
    let openNew = forceNew ?? (node.openNew == true)
    if let command = node.command {
        LibraryStore.shared.recordOpen(node.id)
        runInTerminal(command)
    } else if let path = node.appPath {
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
            guard let value = value ?? promptValue(for: node) else { return }
            link = node.link(filling: value)
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
