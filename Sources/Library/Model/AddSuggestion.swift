import SwiftUI

/// A link or application Library offers to add: what is selected in the app in front, or what was copied.
struct AddSuggestion {
    enum Source { case selection, clipboard }

    let node: LibraryItem
    let source: Source

    var title: String { "Add “\(node.name)” to Library" }

    var subtitle: String {
        "\(source == .selection ? "From your selection" : "From your clipboard") · \(node.url ?? node.appPath ?? "")"
    }

    /// A selected link first, else the link or application on the clipboard. Anything already in the library
    /// is skipped. Needs no hidden step: the menus show the suggestion when there is one.
    static func make(selection: String?, clipboard: ClipItem?, in nodes: [LibraryItem]) -> AddSuggestion? {
        func isNew(_ node: LibraryItem) -> Bool { !nodes.leaves.contains { $0.shareURL == node.shareURL } }
        if let text = selection, let link = QuickOpenResult.link(from: text) {
            let node = LibraryItem(name: link.host ?? link.absoluteString, url: link.absoluteString)
            if isNew(node) { return AddSuggestion(node: node, source: .selection) }
        }
        if let node = clipboard?.libraryNode, isNew(node) {
            return AddSuggestion(node: node, source: .clipboard)
        }
        return nil
    }
}
