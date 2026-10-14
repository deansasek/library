import Foundation

/// One field of a bulk edit. `keep` leaves every item as it is.
enum BulkChange<Value: Hashable>: Hashable {
    case keep
    case clear
    case set(Value)
}

/// The fields of the bulk edit sheet. Only fields that are not `keep` change.
struct BulkEdit: Equatable {
    var icon: BulkChange<String> = .keep
    var color: BulkChange<String> = .keep
    /// True opens in a new tab or window, false reuses the existing one.
    var openNew: BulkChange<Bool> = .keep

    var changesNothing: Bool { icon == .keep && color == .keep && openNew == .keep }

    /// Applies the edit to the items in `ids`, wherever they are in the tree, and returns the new tree.
    /// Color skips dividers, and Opens In skips items with no choice, as the single-item sheet does.
    static func apply(_ edit: BulkEdit, to ids: Set<UUID>, in nodes: [LibraryItem]) -> [LibraryItem] {
        var result = nodes
        for id in ids {
            result.update(id) { edit.change(&$0) }
        }
        return result
    }

    private func change(_ node: inout LibraryItem) {
        switch icon {
        case .keep: break
        case .clear: node.icon = nil
        case .set(let value): node.icon = value
        }
        if node.isDivider != true {
            switch color {
            case .keep: break
            case .clear: node.color = nil
            case .set(let value): node.color = value
            }
        }
        if node.modeLabels != nil {
            switch openNew {
            case .keep: break
            case .clear: node.openNew = nil
            case .set(let value): node.openNew = value ? true : nil
            }
        }
    }
}
