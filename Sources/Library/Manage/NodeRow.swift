import SwiftUI

struct NodeRow: View {
    static let shortcutWidth: CGFloat = 110
    let pathWidth: CGFloat

    let node: LibraryItem
    @ObservedObject var store: LibraryStore
    @ObservedObject var state: ManageState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    if let warning = linkWarning {
                        Image(systemName: warning.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                            .help(warning.help)
                            .accessibilityLabel(warning.label)
                    }
                }
                if let readLater = node.readLater {
                    // A book for unread, a check for read: the Reading List state, shown beside the name.
                    Image(systemName: readLater == .read ? "checkmark.circle" : "book")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        // The book turns into a check in place. Reduce Motion swaps it at once.
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .smooth, value: readLater)
                        .help(readLater == .read ? String(localized: "Read", bundle: L10n.bundle) : String(localized: "Unread", bundle: L10n.bundle))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let shortcuts = node.shortcuts {
                    if store.failedShortcuts.contains(node.id) {
                        Image(systemName: "exclamationmark.triangle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                            .help("A shortcut is in use by another app")
                            .accessibilityLabel("Shortcut in use by another app")
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
        .accessibilityElement(children: state.renamingID == node.id ? .contain : .combine)
        .accessibilityLabel(accessibilityName)
        .draggable(RowDrag(ids: dragIDs, link: node.shareURL))
        .dropDestination(for: RowDrag.self) { drags, _ in
            let moved = Set(drags.flatMap(\.ids))
            let drop = rowDrop(moving: moved, onto: node.id, in: store.nodes, listSorted: state.sortKey != nil)
            store.apply(drop, moving: moved)
            // Always taken, so a drop on a row never falls through to the list's move-to-top-level.
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

    /// The name, kind, target, and shortcut, as VoiceOver reads a row. Adds a warning when a shortcut is in use elsewhere.
    /// The target and shortcut are included so two rows with the same name can be told apart.
    private var accessibilityName: String {
        var label = "\(node.name), \(kindName)"
        if let tag = LibraryItem.colorAccessibilityName(for: node) {
            label += ", \(tag)"
        }
        let target = detail.trimmingCharacters(in: .whitespaces)
        if !target.isEmpty {
            label += ", \(target)"
        }
        if let shortcuts = node.shortcuts, !shortcuts.isEmpty {
            let keys = shortcuts.map(\.description).joined(separator: ", ")
            label += ", " + String(format: String(localized: "shortcut %@", bundle: L10n.bundle), keys)
        }
        if let readLater = node.readLater {
            label += readLater == .read ? ", in Reading List, read" : ", in Reading List, unread"
        }
        if let warning = linkWarning {
            label += ", \(warning.label)"
        }
        if store.failedShortcuts.contains(node.id) {
            label += ", shortcut in use by another app"
        }
        return label
    }

    /// The warning for a bookmark whose last link check failed: a broken page, or a site that could not be reached.
    private var linkWarning: (symbol: String, help: String, label: String)? {
        switch node.linkStatus?.kind {
        case .broken:
            return ("exclamationmark.triangle",
                    String(localized: "Broken link. The page returned an error when Library last checked it.", bundle: L10n.bundle),
                    String(localized: "broken link", bundle: L10n.bundle))
        case .unreachable:
            return ("wifi.exclamationmark",
                    String(localized: "Unreachable link. Library could not reach the site when it last checked it.", bundle: L10n.bundle),
                    String(localized: "unreachable link", bundle: L10n.bundle))
        case .ok, .unknown, nil:
            return nil
        }
    }

    private var kindName: String {
        if node.isDivider == true { return "divider" }
        if node.isFolder { return "folder" }
        if node.appPath != nil { return "application" }
        if node.command != nil { return "terminal command" }
        return "bookmark"
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
    private var dragIDs: [UUID] {
        state.selection.contains(node.id) ? Array(state.selection) : [node.id]
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
