import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Library rows dragged inside the Manage window. Declared in the app's Info.plist (see build.sh).
    static let libraryRows = UTType(exportedAs: "com.deansasek.library.rows")
}

/// What dragging a row carries. Rows move inside the window by their ids. A row with a link also offers the
/// link to other apps, such as a browser. Folders, dividers, and apps offer only the ids.
struct RowDrag: Codable, Sendable, Transferable {
    let ids: [UUID]
    let link: URL?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .libraryRows)
        ProxyRepresentation(exporting: exportLink)
    }

    /// Throws when there is no link, so other apps get no link from a folder or divider.
    private static func exportLink(_ drag: RowDrag) throws -> URL {
        guard let link = drag.link else { throw CocoaError(.fileNoSuchFile) }
        return link
    }
}

/// Where a drop on a row, or on empty space in the list, moves the dragged rows.
enum RowDrop: Equatable {
    /// Into the folder with this id.
    case moveInto(UUID)
    /// Directly before the row with this id, in your own order.
    case moveBefore(UUID)
    /// To the top level, from empty space.
    case moveToTopLevel
    /// Nothing moves.
    case ignore
}

/// The rule for a drop. `targetID` is the row under the drop, or nil for empty space. `nodes` is the whole library,
/// and `listSorted` is true while a column sorts the list, when "before" has no meaning.
/// Items never move into themselves or into their own contents, so those drops are ignored.
func rowDrop(moving ids: Set<UUID>, onto targetID: UUID?, in nodes: [LibraryItem], listSorted: Bool) -> RowDrop {
    guard !ids.isEmpty else { return .ignore }
    guard let targetID else { return .moveToTopLevel }
    let movesIntoItself = ids.contains { nodes.node(withID: $0)?.contains(targetID) == true }
    guard !movesIntoItself, let target = nodes.node(withID: targetID) else { return .ignore }
    if target.isFolder { return .moveInto(targetID) }
    return listSorted ? .ignore : .moveBefore(targetID)
}

extension LibraryStore {
    /// Applies a drop decision as one undoable "Move" step. Ignored drops change nothing.
    func apply(_ drop: RowDrop, moving ids: Set<UUID>) {
        switch drop {
        case .moveInto(let folderID): move(ids, to: folderID)
        case .moveBefore(let targetID): move(ids, before: targetID)
        case .moveToTopLevel: move(ids, to: nil)
        case .ignore: break
        }
    }
}
