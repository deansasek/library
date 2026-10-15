import AppKit

/// Adds screenshots and screen recordings to clipboard history as soon as macOS saves them.
///
/// Spotlight tags every capture with `kMDItemIsScreenCapture`, so a live metadata query reports new captures.
/// No folder is watched, and the pasteboard is never changed. Only captures made after the feature was turned on
/// are added. The newest creation date seen is saved, so a restart does not add the same captures again.
@MainActor
final class ScreenCaptures: ObservableObject {
    static let shared = ScreenCaptures()
    static let enabledKey = "clipboardAddsScreenshots"
    static let sinceKey = "screenshotsSince"
    private static let movieExtensions: Set<String> = ["mov", "mp4", "m4v"]

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                // Turning it on starts from now, so older screenshots are not added.
                UserDefaults.standard.set(Date(), forKey: Self.sinceKey)
                start()
            } else {
                stop()
            }
        }
    }

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var handled: Set<String> = []

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        if isEnabled { start() }
    }

    private func start() {
        guard query == nil else { return }
        if UserDefaults.standard.object(forKey: Self.sinceKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.sinceKey)
        }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemContentCreationDate", ascending: true)]
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.received() }
            })
        }
        self.query = query
        query.start()
    }

    private func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        handled = []
    }

    /// Adds each capture made since the saved date, then moves the date to the newest one.
    private func received() {
        guard isEnabled, let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let since = UserDefaults.standard.object(forKey: Self.sinceKey) as? Date ?? .distantPast
        var newest = since
        var present: Set<String> = []
        for case let result as NSMetadataItem in query.results {
            guard let path = result.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            present.insert(path)
            guard let created = result.value(forAttribute: "kMDItemContentCreationDate") as? Date,
                  created > since, !handled.contains(path) else { continue }
            handled.insert(path)
            newest = max(newest, created)
            ingest(URL(fileURLWithPath: path))
        }
        // A capture that was deleted leaves its reference in history, so the reference goes with it.
        for path in handled.subtracting(present) where !FileManager.default.fileExists(atPath: path) {
            handled.remove(path)
            ClipboardHistory.shared.removeFile(at: URL(fileURLWithPath: path))
        }
        UserDefaults.standard.set(newest, forKey: Self.sinceKey)
    }

    private func ingest(_ url: URL) {
        if Self.movieExtensions.contains(url.pathExtension.lowercased()) {
            // A recording is large, so history keeps a reference to the file, not a copy.
            let reference: [[NSPasteboard.PasteboardType: Data]] = [[.fileURL: Data(url.absoluteString.utf8)]]
            ClipboardHistory.shared.addCapture(reference, source: "Screen Recording")
            return
        }
        Task.detached(priority: .utility) {
            guard let png = Self.pngData(at: url) else { return }
            await MainActor.run {
                ClipboardHistory.shared.addCapture([[.png: png]], source: "Screenshot")
            }
        }
    }

    /// Reads a screenshot and converts it to PNG, the format history stores images in. Nil when it is unreadable
    /// or over the size limit.
    nonisolated private static func pngData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= ClipboardHistory.maxItemBytes,
              let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return png
    }
}
