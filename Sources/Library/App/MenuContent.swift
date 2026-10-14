import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject private var loginItem = LoginItem.shared
    @ObservedObject private var history = ClipboardHistory.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuItems(nodes: store.nodes, store: store, topLevel: true)
        Divider()
        Menu {
            if history.items.isEmpty {
                Button("No Clipboard History") {}
                    .disabled(true)
            } else {
                ForEach(history.displayOrder.prefix(10)) { item in
                    Button {
                        history.copy(item)
                    } label: {
                        Label {
                            Text(item.menuTitle)
                        } icon: {
                            Image(nsImage: item.icon)
                        }
                    }
                }
                Divider()
                Button("Clear History") { history.clear() }
            }
        } label: {
            Label("Clipboard", systemImage: "doc.on.clipboard")
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
            Label("Edit Library…", systemImage: "books.vertical")
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        Divider()
        Toggle("Open at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.set($0) }
        ))
        Button("About Library") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Your bookmarks, apps, and clipboard history, one shortcut away.",
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                 .foregroundColor: NSColor.secondaryLabelColor]),
            ])
        }
        Button("Quit Library") {
            NSApp.terminate(nil)
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
        if topLevel && !store.frequent.isEmpty {
            Section("Frequently Used") {
                rows(store.frequent)
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
