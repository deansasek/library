import AppKit

/// The link check. When the setting is on, it runs once a day while Library runs. File > Check Links runs it now. Each
/// address is requested once per run, and results are stored on the bookmarks without an undo step.
@MainActor
enum LinkChecker {
    /// The UserDefaults key of "Check Links Periodically". Off by default.
    static let enabledKey = "checkLinksPeriodically"
    private static let lastRunKey = "lastLinkCheck"
    /// The first scheduled check waits this long after the setting is read, so it does not compete with launch.
    private static let firstDelay: Duration = .seconds(60)
    private static var scheduleTask: Task<Void, Never>?
    private static var isChecking = false

    /// Starts the daily schedule, or stops it when the setting is off. Called at launch and whenever the setting changes.
    /// Between runs the task sleeps until the next run is due, so nothing wakes up on a timer in the meantime.
    static func startSchedule(store: LibraryStore = .shared) {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        scheduleTask = Task {
            try? await Task.sleep(for: firstDelay)
            while !Task.isCancelled, UserDefaults.standard.bool(forKey: enabledKey) {
                let lastRun = UserDefaults.standard.object(forKey: lastRunKey) as? Date
                if LinkCheck.isDailyCheckDue(now: .now, lastRun: lastRun) {
                    await run(store: store, interactive: false)
                }
                let latest = UserDefaults.standard.object(forKey: lastRunKey) as? Date
                let wait = LinkCheck.secondsUntilDailyCheck(now: .now, lastRun: latest)
                try? await Task.sleep(for: .seconds(max(wait, 60)))
            }
        }
    }

    /// File > Check Links. Works whether or not the daily check is on. It still skips addresses checked in the last 24 hours.
    static func checkNow(store: LibraryStore = .shared) {
        Task { await run(store: store, interactive: true) }
    }

    /// One pass over the bookmarks that are due. An interactive pass reports its outcome in an alert.
    private static func run(store: LibraryStore, interactive: Bool) async {
        guard !isChecking else {
            if interactive { show("Library is already checking your links.") }
            return
        }
        isChecking = true
        defer { isChecking = false }
        let now = Date.now
        UserDefaults.standard.set(now, forKey: lastRunKey)
        let items = LinkCheck.itemsToCheck(store.nodes.leaves, now: now)
        var targets: [String: URL] = [:]
        for item in items {
            if let key = LinkCheck.key(for: item), targets[key] == nil, let link = item.link { targets[key] = link }
        }
        guard !targets.isEmpty else {
            if interactive {
                show(String(localized: "Every bookmark was checked in the last 24 hours, so there was nothing to check.",
                            bundle: L10n.bundle))
            }
            return
        }
        let version = UpdateCheck.currentVersion
        let pending = Array(targets)
        var kinds: [String: LinkStatus.Kind] = [:]
        var next = 0
        await withTaskGroup(of: (String, LinkStatus.Kind?).self) { group in
            func startMore(running: Int) -> Int {
                let count = LinkCheck.startCount(running: running, pending: pending.count - next)
                for _ in 0..<count where !Task.isCancelled {
                    let (key, url) = pending[next]
                    next += 1
                    group.addTask { (key, await LinkProbe.check(url, version: version)) }
                }
                return running + count
            }
            var running = startMore(running: 0)
            for await (key, kind) in group {
                running -= 1
                if let kind { kinds[key] = kind }
                running = startMore(running: running)
            }
        }
        // A check that was cancelled part way records only the answers it got.
        let checkedAt = Date.now
        var updates: [UUID: LinkStatus] = [:]
        for item in items {
            if let key = LinkCheck.key(for: item), let kind = kinds[key] {
                updates[item.id] = LinkStatus(kind: kind, checked: checkedAt)
            }
        }
        store.recordLinkStatuses(updates)
        if interactive {
            let broken = kinds.values.filter { $0 == .broken }.count
            let unreachable = kinds.values.filter { $0 == .unreachable }.count
            show(String(localized: "Checked \(kinds.count) links. \(broken) are broken, and \(unreachable) can’t be reached.",
                        bundle: L10n.bundle))
        }
    }

    private static func show(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Check Links", bundle: L10n.bundle)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
