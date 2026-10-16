import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject private var loginItem = LoginItem.shared
    @ObservedObject private var history = ClipboardHistory.shared
    @ObservedObject private var updates = UpdateStatus.shared
    @ObservedObject private var clipLock = ClipboardLock.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Shown only when an automatic or manual check found a newer version. Choosing it opens the update alert.
        if let version = updates.availableVersion {
            Button {
                UpdateCheck.showAvailable()
            } label: {
                Label {
                    Text("Update Available — Version \(UpdateRules.displayVersion(version))", bundle: L10n.bundle)
                } icon: {
                    Image(systemName: "arrow.down.circle")
                        .symbolRenderingMode(.hierarchical)
                        // Bounces once when an update is found. Reduce Motion leaves it still.
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : version)
                }
            }
            Divider()
        }
        MenuItems(nodes: store.nodes, store: store, topLevel: true)
        Divider()
        Menu {
            if history.items.isEmpty {
                Button {} label: {
                    Text("No Clipboard History", bundle: L10n.bundle)
                }
                    .disabled(true)
            } else {
                ForEach(history.displayOrder.prefix(10)) { item in
                    Button {
                        clipLock.perform(item, for: .copy) { history.copy(item) }
                    } label: {
                        Label {
                            Text(clipLock.menuTitle(for: item))
                        } icon: {
                            Image(nsImage: clipLock.icon(for: item))
                        }
                    }
                }
                Divider()
                Button { history.clear() } label: { Text("Clear History", bundle: L10n.bundle) }
            }
            if !history.pasteQueue.isEmpty {
                Divider()
                Section {
                    ForEach(history.pasteQueue) { item in
                        Button {} label: {
                            Text(clipLock.menuTitle(for: item))
                        }
                        .disabled(true)
                    }
                    Button { history.pasteNext() } label: {
                        Label { Text("Paste Next", bundle: L10n.bundle) } icon: { Image(systemName: "arrow.right.doc.on.clipboard") }
                    }
                    Button { history.clearPasteQueue() } label: { Text("Clear Queue", bundle: L10n.bundle) }
                } header: {
                    Label { Text("Paste Queue (\(history.pasteQueue.count))", bundle: L10n.bundle) } icon: { Image(systemName: "list.number") }
                }
            }
        } label: {
            Label { Text("Clipboard", bundle: L10n.bundle) } icon: { Image(systemName: "doc.on.clipboard") }
        }
        // Shown only when the lock is on. It is greyed out while the pinned items are already locked.
        if clipLock.isRequired {
            Button { clipLock.lockPinned() } label: {
                Label { Text("Lock Pinned Items", bundle: L10n.bundle) } icon: { Image(systemName: "lock") }
            }
            .disabled(!clipLock.state.isUnlocked)
        }
        // Shown only while the clipboard holds a link or application that is not in the library.
        if let suggestion = store.suggestion() {
            Button { store.add(suggestion) } label: {
                Label(suggestion.title, systemImage: "plus.circle")
            }
        }
        Button {
            openWindow(id: "manage")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label { Text("Edit Library…", bundle: L10n.bundle) } icon: { Image(systemName: "books.vertical") }
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label { Text("Settings…", bundle: L10n.bundle) } icon: { Image(systemName: "gearshape") }
        }
        .keyboardShortcut(",")
        Divider()
        Toggle(isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.set($0) }
        )) {
            Text("Open at Login", bundle: L10n.bundle)
        }
        if loginItem.needsApproval {
            Button {
                LoginItem.openSettings()
            } label: {
                Text("Open Login Items…", bundle: L10n.bundle)
            }
        }
        Button {
            UpdateCheck.checkNow()
        } label: {
            Text("Check for Updates…", bundle: L10n.bundle)
        }
        Menu {
            Button("Library Help") { NSWorkspace.shared.open(HelpCommands.guide) }
            Button("Keyboard Shortcuts") { NSWorkspace.shared.open(HelpCommands.shortcuts) }
            Button("Welcome Tour…") { Welcome.show() }
            Divider()
            Button("Report an Issue…") { NSWorkspace.shared.open(HelpCommands.issues) }
            Button("Support Library…") { NSWorkspace.shared.open(HelpCommands.support) }
        } label: {
            Text("Help", bundle: L10n.bundle)
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Your bookmarks, apps, and clipboard history, one shortcut away.",
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                 .foregroundColor: NSColor.secondaryLabelColor]),
            ])
        } label: {
            Text("About Library", bundle: L10n.bundle)
        }
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit Library", bundle: L10n.bundle)
        }
        .keyboardShortcut("q")
    }
}

/// One menu level: items grouped under their divider titles, folders as submenus.
struct MenuItems: View {
    let nodes: [LibraryItem]
    @ObservedObject var store: LibraryStore

    var topLevel = false

    var body: some View {
        // Read once per build, since the list is sorted from the whole library each time it is read.
        let frequent = topLevel ? store.frequent : []
        if !frequent.isEmpty {
            Section("Frequently Used") {
                rows(frequent)
            }
        }
        let reading = topLevel ? ReadingList.ordered(nodes.leaves) : []
        if !reading.isEmpty {
            Section {
                rows(reading)
            } header: {
                Text("Reading List", bundle: L10n.bundle)
            }
        }
        ForEach(Array(nodes.sections.enumerated()), id: \.offset) { _, section in
            if let title = section.title {
                Section(title) {
                    rows(section.nodes)
                }
            } else {
                rows(section.nodes)
            }
        }
    }

    private func rows(_ nodes: [LibraryItem]) -> some View {
        ForEach(nodes) { node in
            if let children = node.children {
                Menu {
                    if children.isEmpty {
                        Button("Empty") {}
                            .disabled(true)
                    } else {
                        if node.showsOpenAllItem {
                            Button("Open All") { openAll(children) }
                                .disabled(openAllSelection(in: children).isEmpty)
                            Divider()
                        }
                        MenuItems(nodes: children, store: store)
                    }
                } label: {
                    Label {
                        Text(node.name)
                    } icon: {
                        Image(nsImage: store.icon(for: node))
                    }
                }
            } else {
                Button {
                    // Holding Option flips the item's new-window or new-instance setting.
                    let flip = NSEvent.modifierFlags.contains(.option)
                    open(node, forceNew: flip ? node.openNew != true : nil)
                } label: {
                    Label {
                        Text(node.name)
                    } icon: {
                        Image(nsImage: store.icon(for: node))
                    }
                }
                .help(node.url ?? node.command ?? node.appPath ?? "")
                .keyboardShortcut(node.shortcuts?.first { $0.openNew == (node.openNew == true) }?.menuShortcut)
                .disabled(node.appPath.map { !FileManager.default.fileExists(atPath: $0) } ?? false)
            }
        }
    }
}
