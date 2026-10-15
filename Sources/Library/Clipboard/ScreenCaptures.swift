import AppKit

/// Adds screenshots and screen recordings to clipboard history as soon as macOS saves them.
///
/// Spotlight tags every capture with `kMDItemIsScreenCapture`, so a live metadata query reports new captures.
/// No folder is watched, and the pasteboard is never changed. Only captures made after the feature was turned on
/// are added. The saved date moves forward only past captures that are added, so a capture that could not be read
/// yet is tried again on a later update, and after a restart.
/// The result of reading a screenshot.
enum ScreenshotRead {
    case png(Data)
    /// Over the size limit. Never added, so it is not retried.
    case tooLarge
    /// Not readable yet, for example while macOS is still writing the file.
    case unreadable
}

@MainActor
final class ScreenCaptures: ObservableObject {
    static let shared = ScreenCaptures()
    static let enabledKey = "clipboardAddsScreenshots"
    static let sinceKey = "screenshotsSince"
    private static let movieExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// What happened to one capture. A capture that could not be read yet stays pending and is retried.
    private enum Outcome { case added, skipped, retry }

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
    /// Captures already added, or skipped for good.
    private var handled: Set<String> = []
    /// Captures being read now.
    private var inFlight: Set<String> = []
    /// Captures seen but not added yet, with their creation dates.
    private var pending: [String: Date] = [:]
    /// The newest creation date among captures that are finished.
    private var finishedNewest: Date = .distantPast

    /// Off unless the user turned it on. Screenshots do not pass through the privacy filters that copies do,
    /// so a screenshot of a password manager could be kept, and only a user who accepts that should opt in.
    nonisolated static func initialEnabled(stored: Any?) -> Bool {
        stored as? Bool ?? false
    }

    private init() {
        isEnabled = Self.initialEnabled(stored: UserDefaults.standard.object(forKey: Self.enabledKey))
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
        inFlight = []
        pending = [:]
        finishedNewest = .distantPast
    }

    /// Starts each capture made since the saved date, and retries the ones still pending.
    private func received() {
        guard isEnabled, let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let since = UserDefaults.standard.object(forKey: Self.sinceKey) as? Date ?? .distantPast
        var present: Set<String> = []
        for case let result as NSMetadataItem in query.results {
            guard let path = result.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let created = result.value(forAttribute: "kMDItemContentCreationDate") as? Date else { continue }
            present.insert(path)
            guard !handled.contains(path), !inFlight.contains(path), created > since || pending[path] != nil else { continue }
            pending[path] = created
            inFlight.insert(path)
            ingest(URL(fileURLWithPath: path), created: created)
        }
        // A capture that was deleted leaves its reference in history, so the reference goes with it.
        for path in handled.subtracting(present) where !FileManager.default.fileExists(atPath: path) {
            handled.remove(path)
            ClipboardHistory.shared.removeFile(at: URL(fileURLWithPath: path))
        }
        // A pending capture that was deleted before it could be read is dropped, so it does not hold the date back.
        for path in Array(pending.keys) where !inFlight.contains(path) && !FileManager.default.fileExists(atPath: path) {
            pending.removeValue(forKey: path)
        }
        saveProgress(since: since)
    }

    private func ingest(_ url: URL, created: Date) {
        let path = url.path
        if Self.movieExtensions.contains(url.pathExtension.lowercased()) {
            // A recording is large, so history keeps a reference to the file, not a copy.
            let reference: [[NSPasteboard.PasteboardType: Data]] = [[.fileURL: Data(url.absoluteString.utf8)]]
            ClipboardHistory.shared.addCapture(reference, source: "Screen Recording")
            finish(path, created: created, .added)
            return
        }
        Task.detached(priority: .utility) {
            let read = Self.readPNG(at: url)
            await MainActor.run {
                switch read {
                case .png(let png):
                    ClipboardHistory.shared.addCapture([[.png: png]], source: "Screenshot")
                    ScreenCaptures.shared.finish(path, created: created, .added)
                case .tooLarge:
                    ScreenCaptures.shared.finish(path, created: created, .skipped)
                case .unreadable:
                    ScreenCaptures.shared.finish(path, created: created, .retry)
                }
            }
        }
    }

    private func finish(_ path: String, created: Date, _ outcome: Outcome) {
        inFlight.remove(path)
        switch outcome {
        case .added, .skipped:
            handled.insert(path)
            pending.removeValue(forKey: path)
            finishedNewest = max(finishedNewest, created)
        case .retry:
            break
        }
    }

    /// Moves the saved date to the newest finished capture, but not past a capture still waiting, so a restart
    /// picks that one up again.
    private func saveProgress(since: Date) {
        guard finishedNewest > since else { return }
        let target = pending.values.min().map { min($0, finishedNewest) } ?? finishedNewest
        if target > since {
            UserDefaults.standard.set(target, forKey: Self.sinceKey)
        }
    }

    /// Reads a screenshot and converts it to PNG, the format history stores images in.
    nonisolated static func readPNG(at url: URL) -> ScreenshotRead {
        // The size comes from the file's attributes, so a huge file is never read into memory.
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return .unreadable }
        guard size <= ClipboardHistory.maxItemBytes else { return .tooLarge }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard data.count <= ClipboardHistory.maxItemBytes else { return .tooLarge }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return .unreadable }
        return .png(png)
    }
}
