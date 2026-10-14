import AppKit
import LocalAuthentication
import SwiftUI

/// The lock on pinned clipboard items, as a pure state machine. Nothing here touches the UI or LocalAuthentication,
/// so the checks run every transition. The state is in memory only: a new session starts locked.
struct PinnedLock: Equatable {
    /// Whether a pinned item may be shown or copied without asking first.
    enum Access: Equatable {
        case now
        case afterAuthentication
    }

    /// True from a successful authentication until the lock is engaged again.
    private(set) var isUnlocked = false
    /// Counts engagements. A prompt that began before the lock was engaged must not unlock the items after it.
    private(set) var generation = 0

    /// Starts locked. Quitting Library ends the session, so the next launch starts here again.
    init() {}

    /// Records the answer to a prompt. Only a success unlocks. A cancelled or failed prompt changes nothing, and a
    /// prompt that began before the last engagement is ignored.
    mutating func finishAuthentication(succeeded: Bool, startedAt start: Int) {
        guard succeeded, start == generation else { return }
        isUnlocked = true
    }

    /// Engages the lock: the user chose Lock Pinned Items, the Mac went to sleep, or protection was turned on.
    mutating func lock() {
        isUnlocked = false
        generation += 1
    }

    /// Going to sleep locks the items, the same as the Lock Pinned Items command.
    mutating func systemWillSleep() {
        lock()
    }

    /// Whether a copy or a view of an item can happen now, or only after the user authenticates. Unpinned items and
    /// the setting being off never need it.
    static func access(pinned: Bool, required: Bool, unlocked: Bool) -> Access {
        pinned && required && !unlocked ? .afterAuthentication : .now
    }

    /// The text a row shows: the item's own text, or Pinned Item while it is locked.
    static func displayed(_ text: String, pinned: Bool, required: Bool, unlocked: Bool) -> String {
        access(pinned: pinned, required: required, unlocked: unlocked) == .now
            ? text : String(localized: "Pinned Item", bundle: L10n.bundle)
    }
}

/// The app's lock: the setting, the state, and the prompt. Menus, Quick Open, and Quick Look go through `perform`,
/// so a locked item's text is neither shown nor copied until the user authenticates.
@MainActor
final class ClipboardLock: ObservableObject {
    static let shared = ClipboardLock()

    /// What the prompt is for. It changes only the wording the system shows.
    enum Purpose {
        case show
        case copy
    }

    @Published private(set) var state = PinnedLock()
    /// The setting, Require Touch ID or password to show pinned items. Off by default. Turning it on locks at once.
    @Published var isRequired: Bool {
        didSet {
            UserDefaults.standard.set(isRequired, forKey: "clipboardRequiresAuthentication")
            if isRequired { state.lock() }
        }
    }
    /// True while the system prompt is up. Quick Open stays open then, since the prompt takes the focus.
    private(set) var isPrompting = false
    /// The prompt in progress. A request made meanwhile waits for the same answer instead of prompting again.
    private var prompt: Task<Bool, Never>?

    private init() {
        isRequired = UserDefaults.standard.object(forKey: "clipboardRequiresAuthentication") as? Bool ?? false
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.systemWillSleep() }
        }
    }

    /// True when the item's text must be authenticated for before it is shown or copied.
    func isHidden(_ item: ClipItem) -> Bool {
        PinnedLock.access(pinned: item.pinned, required: isRequired, unlocked: state.isUnlocked) == .afterAuthentication
    }

    /// The title for a list row.
    func title(for item: ClipItem) -> String {
        PinnedLock.displayed(item.title, pinned: item.pinned, required: isRequired, unlocked: state.isUnlocked)
    }

    /// The title for a menu, shortened as ClipItem shortens it.
    func menuTitle(for item: ClipItem) -> String {
        PinnedLock.displayed(item.menuTitle, pinned: item.pinned, required: isRequired, unlocked: state.isUnlocked)
    }

    /// The icon for a row or menu item. A locked item shows a lock instead of its picture or file icon.
    func icon(for item: ClipItem) -> NSImage {
        guard isHidden(item) else { return item.icon }
        return NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage()
    }

    /// Runs `work` now when the item may be shown or copied, or once the user authenticates. When the prompt is
    /// cancelled or unavailable, `work` does not run.
    func perform(_ item: ClipItem, for purpose: Purpose, _ work: @escaping @MainActor () -> Void) {
        guard isHidden(item) else {
            work()
            return
        }
        Task {
            if await authenticate(for: purpose) { work() }
        }
    }

    /// Engages the lock. Used by the Lock Pinned Items command.
    func lockPinned() {
        state.lock()
    }

    /// Asks for Touch ID or the Mac password, unless the items are already unlocked. Returns whether they are now.
    func authenticate(for purpose: Purpose) async -> Bool {
        if state.isUnlocked { return true }
        if let prompt { return await prompt.value }
        let start = state.generation
        let reason: String
        switch purpose {
        case .show: reason = String(localized: "view a pinned clipboard item", bundle: L10n.bundle)
        case .copy: reason = String(localized: "copy a pinned clipboard item", bundle: L10n.bundle)
        }
        let task = Task { @MainActor () -> Bool in
            isPrompting = true
            defer {
                isPrompting = false
                prompt = nil
            }
            let succeeded = await LockAuthentication.evaluate(reason: reason)
            state.finishAuthentication(succeeded: succeeded, startedAt: start)
            return state.isUnlocked
        }
        prompt = task
        return await task.value
    }
}

/// The only code that talks to LocalAuthentication. The policy offers Touch ID and falls back to the Mac password, so
/// a Mac without Touch ID still works. Every failure is a plain "not authenticated".
enum LockAuthentication {
    /// True only when the user passes. Cancelling, failing, or a Mac that cannot authenticate leaves the items locked.
    static func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("Library: pinned clipboard items stay locked, because authentication is unavailable: \(error?.code ?? 0)")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
