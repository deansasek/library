import SwiftUI

/// One copied item with every format it was copied in, so copying it back loses nothing.
struct ClipItem: Identifiable {
    enum Kind { case text, link, image, file, other }

    let id = UUID()
    let representations: [[NSPasteboard.PasteboardType: Data]]
    let digest: String
    let kind: Kind
    /// One line shown in lists.
    let title: String
    /// The text, for searching and for copying as plain text.
    let plainText: String?
    let link: URL?
    /// A small picture of an image item, for lists and menus.
    let thumbnail: NSImage?
    /// The animated GIF a copied web image points at, when its HTML names one.
    let gifURL: URL?
    /// The files, for a file copy.
    let fileURLs: [URL]
    var byteCount: Int
    var date = Date()
    var pinned = false
    /// The GIF downloaded from `gifURL`. Browsers copy only a still picture of a GIF.
    var animatedData: Data?
    /// The app that was in front when it was copied.
    var sourceApp: String?
    /// Lowercased title and text, built once when the copy is captured, so searching does not rebuild it.
    var searchText = ""

    /// The icon in lists and menus: a thumbnail for a picture, the file's icon for a file, else a symbol.
    var icon: NSImage {
        if let thumbnail { return thumbnail }
        if kind == .file, let path = fileURLs.first?.path { return appIcon(at: path) }
        return symbolImage(pinned ? "pin.fill" : symbol) ?? NSImage()
    }

    var symbol: String {
        switch kind {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .other: return "doc.on.clipboard"
        }
    }

    static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

    /// True for a copied GIF, or a copied GIF file.
    var isAnimated: Bool {
        animatedData != nil || representations.first?[Self.gifType] != nil || fileURLs.contains { $0.pathExtension.lowercased() == "gif" }
    }

    /// The GIF as an image that plays when shown in an image view. Decoded when asked, not kept.
    func loadAnimated() -> NSImage? {
        if let animatedData { return NSImage(data: animatedData) }
        if let data = representations.first?[Self.gifType] { return NSImage(data: data) }
        return fileURLs.first { $0.pathExtension.lowercased() == "gif" }.flatMap { NSImage(contentsOf: $0) }
    }

    /// The picture, for an image item. Decoded when asked, not kept.
    var image: NSImage? {
        guard kind == .image, let first = representations.first, let data = first[.png] ?? first[.tiff] else { return nil }
        return NSImage(data: data)
    }

    /// The title for a menu, cut short so a long copy does not make the menu wide.
    var menuTitle: String {
        title.count > 60 ? String(title.prefix(60)) + "…" : title
    }

    /// What Add to Library would create: a bookmark for a link, an app item for a copied application.
    var libraryNode: LibraryItem? {
        if let link, WebFetch.isWeb(link) { return LibraryItem(name: link.host ?? link.absoluteString, url: link.absoluteString) }
        if let app = fileURLs.first(where: { $0.pathExtension == "app" }) {
            return LibraryItem(name: appName(at: app.path), appPath: app.path)
        }
        return nil
    }

    /// The pasteboard types that are plain text, so a copy carrying several of them is still plain text. A copy from a
    /// browser or a notes app can hold UTF-8, UTF-16 and a legacy string type all at once, and dropping those would
    /// drop nothing.
    static let plainTextTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType.string,
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text-le"),
        NSPasteboard.PasteboardType("public.utf16-plain-text-be"),
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("com.apple.utf16-text"),
    ]

    /// True when copying as plain text would drop formatting. A text clip counts only when its first pasteboard item
    /// holds a type that is not a plain-text flavor, such as RTF, HTML, or PDF.
    var hasRichFormats: Bool {
        guard kind == .text, let types = representations.first else { return false }
        return types.contains { !Self.plainTextTypes.contains($0.key) }
    }

    @MainActor private static let times: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// How long ago it was copied, and what it is.
    @MainActor var subtitle: String {
        // A locked pinned item hides its text, and its source app and age go with it, so only its kind and pin show.
        if ClipboardLock.shared.isHidden(self) { return "Pinned · \(kindName)" }
        let parts = [pinned ? "Pinned" : nil, sourceApp, Self.times.localizedString(for: date, relativeTo: Date()), kindName]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// The kind as a word, such as Text or Link.
    var kindName: String {
        let name: String
        switch kind {
        case .text: name = "Text"
        case .link: name = "Link"
        case .image: name = "Image"
        case .file: name = "File"
        case .other: name = "Item"
        }
        return name
    }
}
