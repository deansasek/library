import SwiftUI

struct NodeRow: View {
    static let shortcutWidth: CGFloat = 110
    let pathWidth: CGFloat

    let node: LibraryItem
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: store.icon(for: node))
                    .accessibilityHidden(true)
                if state.renamingID == node.id {
                    NameField(text: Binding(
                        get: { node.name },
                        set: { store.rename(node.id, to: $0) }
                    )) {
                        store.endRename()
                        state.renamingID = nil
                    }
                } else {
                    Text(node.name)
                        .fontWeight(node.isDivider == true ? .semibold : .regular)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let shortcuts = node.shortcuts {
                    if store.failedShortcuts.contains(node.id) {
                        Image(systemName: "exclamationmark.triangle")
                            .help("A shortcut is in use by another app")
                    }
                    Text(shortcuts.map(\.description).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .frame(width: Self.shortcutWidth, alignment: .leading)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: pathWidth, alignment: .leading)
        }
        .onDrag {
            // The ids move rows inside this window. A link or app file can also be dropped into other apps.
            let provider = NSItemProvider()
            provider.registerObject(dragPayload as NSString, visibility: .ownProcess)
            if let url = node.shareURL {
                provider.registerObject(url as NSURL, visibility: .all)
            }
            return provider
        }
        .dropDestination(for: String.self) { items, _ in
            let moved = Set(items.flatMap(ids(in:)))
            if node.isFolder {
                store.move(moved, to: node.id)
            } else if state.sortKey == nil {
                // "Before" means nothing while the list is sorted, so only your own order accepts it.
                store.move(moved, before: node.id)
            }
            return true
        } isTargeted: { targeted in
            if targeted {
                state.dropTarget = node.id
            } else if state.dropTarget == node.id {
                state.dropTarget = nil
            }
        }
        .overlay(alignment: node.isFolder ? .center : .top) {
            // A folder gets an outline, any other row a line where the dropped items will land.
            if state.dropTarget == node.id {
                if node.isFolder {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                } else {
                    Capsule().fill(Color.accentColor).frame(height: 3)
                }
            }
        }
    }

    /// What the item opens, plus its behavior when it is not the default.
    private var detail: String {
        let target = node.url ?? node.command ?? [node.appPath, node.arguments].compactMap { $0 }.joined(separator: " ")
        var parts = [target]
        if let browser = node.browser, let name = installedBrowsers().first(where: { $0.id == browser })?.name {
            parts.append(name)
        }
        if node.openNew == true, let label = node.modeLabels?.new {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }

    /// Dragging a selected row carries the whole selection.
    private var dragPayload: String {
        let ids = state.selection.contains(node.id) ? state.selection : [node.id]
        return ids.map(\.uuidString).joined(separator: ",")
    }
}

struct NameField: View {
    @Binding var text: String
    let onEnd: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .focused($focused)
            .onSubmit(onEnd)
            .onExitCommand(perform: onEnd)
            .task {
                // Wait for the context menu to close, or it takes the focus back.
                try? await Task.sleep(nanoseconds: 150_000_000)
                focused = true
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused && !isFocused { onEnd() }
            }
    }
}
