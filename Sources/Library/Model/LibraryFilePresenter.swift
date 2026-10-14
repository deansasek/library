import Foundation

/// Tells the library when its iCloud copy changes, through NSFilePresenter. Writes that go through
/// `NSFileCoordinator(filePresenter:)` with this presenter do not come back to it, so Library's own saves are not
/// reported as changes from another Mac.
final class LibraryFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    /// Runs on the main queue, where the library reads changes.
    var onChange: (@MainActor () -> Void)?

    init(url: URL) {
        presentedItemURL = url
    }

    func presentedItemDidChange() {
        notify()
    }

    func presentedItemDidGain(_ version: NSFileVersion) {
        notify()
    }

    func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        notify()
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        notify()
        completionHandler(nil)
    }

    /// Runs after the callback returns, so the library can read the file without being inside the coordinator's callback.
    private func notify() {
        Task { @MainActor in onChange?() }
    }
}
