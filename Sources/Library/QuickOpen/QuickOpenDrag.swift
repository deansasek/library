import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What dragging a Quick Open row into another app carries. `payload(for:clipHidden:)` picks it from the row alone,
/// so the choice has no side effects. The picture, file, or text is read only when a drop asks for it.
enum QuickOpenDrag: Equatable, Sendable, Transferable {
    /// A bookmark, a link, or a link's address. Drops as its address.
    case link(URL)
    /// A file copied in the clipboard. Drops as the file.
    case file(URL)
    /// Plain text, such as a snippet or a copied text clip.
    case text(String)
    /// A copied picture in PNG, or in TIFF when that is all the copy held.
    case png(Data)
    case tiff(Data)
    /// Nothing to offer, such as a folder, an app, or a locked clip. The drag still starts, as it always has.
    case nothing

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: exportLink)
        ProxyRepresentation(exporting: exportText)
        FileRepresentation(exportedContentType: .item, exporting: exportFile)
        DataRepresentation(exportedContentType: .png, exporting: exportPNG)
        DataRepresentation(exportedContentType: .tiff, exporting: exportTIFF)
    }

    /// Each export throws unless this drag carries that content, so other formats are not offered.
    private static func exportLink(_ drag: QuickOpenDrag) throws -> URL {
        guard case .link(let url) = drag else { throw CocoaError(.fileNoSuchFile) }
        return url
    }

    private static func exportText(_ drag: QuickOpenDrag) throws -> String {
        guard case .text(let text) = drag else { throw CocoaError(.fileNoSuchFile) }
        return text
    }

    private static func exportFile(_ drag: QuickOpenDrag) throws -> SentTransferredFile {
        guard case .file(let url) = drag else { throw CocoaError(.fileNoSuchFile) }
        return SentTransferredFile(url)
    }

    private static func exportPNG(_ drag: QuickOpenDrag) throws -> Data {
        guard case .png(let data) = drag else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    private static func exportTIFF(_ drag: QuickOpenDrag) throws -> Data {
        guard case .tiff(let data) = drag else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    /// What a row drags. `clipHidden` is true for a locked pinned clip, which drags nothing.
    /// A clip drags its picture first, then its file, then its text, as the copy holds them.
    static func payload(for kind: QuickOpenResult.Kind, clipHidden: Bool) -> QuickOpenDrag {
        switch kind {
        case .clip(let item):
            return clipHidden ? .nothing : clipPayload(item)
        case .item(let node, _):
            return node.shareURL.map { .link($0) } ?? .nothing
        case .openLink(let url), .addLink(let url):
            return .link(url)
        case .snippet(let snippet):
            return .text(snippet.text)
        case .addSuggestion:
            return .nothing
        }
    }

    private static func clipPayload(_ item: ClipItem) -> QuickOpenDrag {
        if item.kind == .image, let first = item.representations.first {
            if let png = first[.png] { return .png(png) }
            if let tiff = first[.tiff] { return .tiff(tiff) }
        }
        if let url = item.fileURLs.first { return .file(url) }
        if let text = item.plainText { return .text(text) }
        return .nothing
    }
}
