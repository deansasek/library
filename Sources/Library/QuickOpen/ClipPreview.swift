import AppKit
import Combine
import Quartz

/// Picks the file the system Quick Look panel shows for a clip, writing a temporary file when the clip has no file.
enum ClipPreviewSource {
    /// What a preview of a clip needs: a file that already exists, or bytes to write to a new file. Planning reads
    /// only the clip's data, so it is cheap on the main actor. Writing the bytes is not.
    enum Plan: Equatable {
        case file(URL)
        case write(Data, ext: String)
    }

    /// The folder for temporary preview files. Only files written here are deleted by ClipPreview.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LibraryPreview", isDirectory: true)
    }

    /// What to preview for an item, or nil when there is nothing to show. Pictures, GIFs, and text are to be written
    /// with a matching extension. Files are previewed where they are.
    static func plan(for item: ClipItem) -> Plan? {
        if item.isAnimated {
            if let file = item.fileURLs.first(where: { $0.pathExtension.lowercased() == "gif" }) { return .file(file) }
            guard let data = item.animatedData ?? item.representations.first?[ClipItem.gifType] else { return nil }
            return .write(data, ext: "gif")
        }
        switch item.kind {
        case .file:
            return item.fileURLs.first.map { .file($0) }
        case .image:
            guard let first = item.representations.first else { return nil }
            if let png = first[.png] { return .write(png, ext: "png") }
            if let tiff = first[.tiff] { return .write(tiff, ext: "tiff") }
            return nil
        case .text, .link:
            guard let text = item.plainText ?? item.link?.absoluteString else { return nil }
            return .write(Data(text.utf8), ext: "txt")
        case .other:
            return nil
        }
    }

    /// The file to preview for an item, or nil when there is nothing to show. Pictures, GIFs, and text are
    /// written into `directory` with a matching extension. Files are previewed where they are.
    static func url(for item: ClipItem, in directory: URL) -> URL? {
        switch plan(for: item) {
        case .file(let url)?: return url
        case .write(let data, let ext)?: return write(data, extension: ext, in: directory)
        case nil: return nil
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

/// Shows the selected clip in the system Quick Look panel. Files written for clips are kept for the time the panel
/// is open, one per clip, and deleted when it closes. The panel is ordered front without taking the key
/// window. The user can click into it, and Quick Open stays open meanwhile (see QuickOpenPanel).
@MainActor
final class ClipPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = ClipPreview()

    /// How long a selection must rest before its preview is written and shown. Arrow keys that pass over several
    /// clips write only the clip where they stop.
    static let followDelay: Duration = .milliseconds(150)

    /// The file being previewed.
    private var file: URL?
    /// The clip being previewed or waiting to be, to tell whether the selection moved to another one.
    private var itemID: UUID?
    /// Files written for clips while the panel is open, by clip id. All are deleted when the panel closes.
    private var written: [UUID: URL] = [:]
    /// The selection change waiting out `followDelay`. Each new change cancels the one before.
    private var followTask: Task<Void, Never>?
    /// The write for the clip waiting to be shown, off the main actor.
    private var writeTask: Task<Void, Never>?
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

    /// Follows the selection while the preview is open. The change is shown once the selection has rested for
    /// `followDelay`. A selection with nothing to preview closes it.
    func follow(_ item: ClipItem?) {
        guard isOpen else { return }
        followTask?.cancel()
        followTask = nil
        // A locked item is not previewed until the user asks, so the preview closes on it too.
        guard let item else {
            close()
            return
        }
        // Back on the clip already shown or requested, so nothing changes.
        guard item.id != itemID else { return }
        followTask = Task { [weak self] in
            try? await Task.sleep(for: ClipPreview.followDelay)
            guard !Task.isCancelled, let self else { return }
            if !self.show(item) { self.close() }
        }
    }

    /// Shows the clip now. A clip with no file yet is written off the main actor, then shown if it is still the
    /// selection. Returns false when the clip has nothing to preview.
    @discardableResult
    func show(_ item: ClipItem) -> Bool {
        writeTask?.cancel()
        writeTask = nil
        lockObserver = nil
        guard let plan = ClipPreviewSource.plan(for: item) else {
            itemID = nil
            return false
        }
        itemID = item.id
        shownItem = item
        lockObserver = ClipboardLock.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            MainActor.assumeIsolated { self?.closeIfLocked() }
        }

        switch plan {
        case .file(let url):
            present(url)
        case .write(let data, let ext):
            if let cached = written[item.id] {
                present(cached)
                return true
            }
            let id = item.id
            let directory = ClipPreviewSource.directory
            writeTask = Task { [weak self] in
                let url = await Task.detached(priority: .userInitiated) {
                    ClipPreviewSource.write(data, extension: ext, in: directory)
                }.value
                guard let self else { return }
                // A file written for a clip that is no longer selected is still kept, so it is deleted with the rest.
                if let url { self.written[id] = url }
                guard self.itemID == id else { return }
                if let url { self.present(url) } else { self.close() }
            }
        }
        return true
    }

    /// Shows a file in the panel, opening the panel when it is not open yet.
    private func present(_ url: URL) {
        file = url
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        // Shown with orderFront, not makeKey, so opening a preview does not move the key away from Quick Open.
        panel.reloadData()
        panel.orderFront(nil)
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endSession() }
            }
        }
        if keyMonitor == nil {
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
        }
    }

    /// Closes the panel. Its close notification removes the temporary files.
    func close() {
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().close() }
        endSession()
    }

    /// Closes the preview when the clip it shows has become locked, so its text does not stay on screen.
    private func closeIfLocked() {
        guard isOpen, let shownItem, ClipboardLock.shared.isHidden(shownItem) else { return }
        close()
    }

    /// Ends the preview: stops watching the panel, cancels pending work, and deletes the files written for it.
    private func endSession() {
        followTask?.cancel()
        followTask = nil
        writeTask?.cancel()
        writeTask = nil
        lockObserver = nil
        shownItem = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        for url in written.values { try? FileManager.default.removeItem(at: url) }
        written = [:]
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
