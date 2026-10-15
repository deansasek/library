import AppKit
import Combine
import Quartz

/// Picks the file the system Quick Look panel shows for a clip, writing a temporary file when the clip has no file.
enum ClipPreviewSource {
    /// The folder for temporary preview files. Only files written here are deleted by ClipPreview.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LibraryPreview", isDirectory: true)
    }

    /// The file to preview for an item, or nil when there is nothing to show. Pictures, GIFs, and text are
    /// written into `directory` with a matching extension. Files are previewed where they are.
    static func url(for item: ClipItem, in directory: URL) -> URL? {
        if item.isAnimated {
            if let file = item.fileURLs.first(where: { $0.pathExtension.lowercased() == "gif" }) { return file }
            guard let data = item.animatedData ?? item.representations.first?[ClipItem.gifType] else { return nil }
            return write(data, extension: "gif", in: directory)
        }
        switch item.kind {
        case .file:
            return item.fileURLs.first
        case .image:
            guard let first = item.representations.first else { return nil }
            if let png = first[.png] { return write(png, extension: "png", in: directory) }
            if let tiff = first[.tiff] { return write(tiff, extension: "tiff", in: directory) }
            return nil
        case .text, .link:
            guard let text = item.plainText ?? item.link?.absoluteString else { return nil }
            return write(Data(text.utf8), extension: "txt", in: directory)
        case .other:
            return nil
        }
    }

    /// Writes the data to a new uniquely named file. Returns nil if the file could not be written. The file is only
    /// readable by you, since a copy can hold text that was never meant for other users.
    static func write(_ data: Data, extension ext: String, in directory: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { return nil }
            return file
        } catch {
            return nil
        }
    }

    /// Deletes the preview folder with whatever a previous run left in it. A preview is removed when its panel
    /// closes, but a quit or a crash while one is open leaves its copy behind. Called once at launch, when no
    /// preview can be open.
    static func removeLeftovers(in directory: URL = ClipPreviewSource.directory) {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Shows the selected clip in the system Quick Look panel. It keeps one temporary file at a time and deletes it
/// when the panel closes or the next preview replaces it. The panel is ordered front without taking the key
/// window. The user can click into it, and Quick Open stays open meanwhile (see QuickOpenPanel).
@MainActor
final class ClipPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = ClipPreview()

    /// The file being previewed.
    private var file: URL?
    /// The clip being previewed, to tell whether the selection moved to another one.
    private var itemID: UUID?
    /// A file this preview wrote and must delete. Files a clip already had are never deleted.
    private var ownedFile: URL?
    private var keyMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    /// The clip being previewed, kept so the lock can tell whether it is now hidden.
    private var shownItem: ClipItem?
    /// Watches the lock while a clip is previewed. The lock can engage at any time, from any menu or from sleep.
    private var lockObserver: AnyCancellable?

    var isOpen: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Opens the preview for a clip, or closes it if it is already showing that clip.
    /// Returns false when the clip has nothing to preview.
    @discardableResult
    func toggle(_ item: ClipItem) -> Bool {
        if isOpen && itemID == item.id {
            close()
            return true
        }
        return show(item)
    }

    /// Follows the selection while the preview is open. A selection with nothing to preview closes it.
    func follow(_ item: ClipItem?) {
        guard isOpen else { return }
        // A locked item is not previewed until the user asks, so the preview closes on it too.
        guard let item else {
            close()
            return
        }
        guard item.id != itemID else { return }
        if !show(item) { close() }
    }

    @discardableResult
    func show(_ item: ClipItem) -> Bool {
        discard()
        guard let url = ClipPreviewSource.url(for: item, in: ClipPreviewSource.directory) else { return false }
        if url.path.hasPrefix(ClipPreviewSource.directory.path) { ownedFile = url }
        file = url
        itemID = item.id
        shownItem = item
        lockObserver = ClipboardLock.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            MainActor.assumeIsolated { self?.closeIfLocked() }
        }

        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        // Shown with orderFront, not makeKey, so opening a preview does not move the key away from Quick Open.
        panel.reloadData()
        panel.orderFront(nil)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.discard() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape closes the preview before anything else, including Quick Open, whichever window has the key.
            guard event.keyCode == 53, let self else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard self.isOpen else { return false }
                self.close()
                return true
            }
            return handled ? nil : event
        }
        return true
    }

    /// Closes the panel. Its close notification removes the temporary file.
    func close() {
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().close() }
        discard()
    }

    /// Closes the preview when the clip it shows has become locked, so its text does not stay on screen.
    private func closeIfLocked() {
        guard isOpen, let shownItem, ClipboardLock.shared.isHidden(shownItem) else { return }
        close()
    }

    private func discard() {
        lockObserver = nil
        shownItem = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        if let ownedFile { try? FileManager.default.removeItem(at: ownedFile) }
        ownedFile = nil
        file = nil
        itemID = nil
    }

    // The panel calls these on the main thread, so the main-actor state can be read through assumeIsolated.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { file == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { file as NSURL? }
    }
}
