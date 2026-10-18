import AppKit

/// The parts of the update check that do not touch the network or the screen. Tested in Tests/Checks/main.swift.
enum UpdateRules {
    /// The most seconds the whole check may take, from the request to the last byte. The request timeout only counts
    /// idle time, so a response fed slowly would otherwise hold up every later automatic check.
    static let resourceTimeout: TimeInterval = 20

    /// The configuration for the check's session: ephemeral, so nothing is cached or stored, with the whole request
    /// capped at `resourceTimeout`.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    /// The numbers in a version such as "1.10.0" or "v1.10.0". Returns nil for anything else ("latest", "1.x",
    /// "1..2", "+1.0", "1.0-beta"), so a bad tag never claims an update.
    static func numbers(_ version: String) -> [Int]? {
        var text = Substring(version)
        if text.first == "v" { text = text.dropFirst() }
        var result: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(part) else { return nil }
            result.append(number)
        }
        return result.isEmpty ? nil : result
    }

    /// Whether `latest` is a higher version than `current`, compared part by part as numbers. A missing part counts
    /// as 0, so "1.9" equals "1.9.0". Returns nil when either one is not a version.
    static func isNewer(_ latest: String, than current: String) -> Bool? {
        guard let latestParts = numbers(latest), let currentParts = numbers(current) else { return nil }
        for index in 0..<max(latestParts.count, currentParts.count) {
            let a = index < latestParts.count ? latestParts[index] : 0
            let b = index < currentParts.count ? currentParts[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// The version as people read it: the tag without its leading "v", as in "1.10.0" for "v1.10.0".
    static func displayVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// The `tag_name` of GitHub's latest-release response, or nil when the response has none.
    static func tag(inReleaseJSON data: Data) -> String? {
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        return (try? JSONDecoder().decode(Release.self, from: data))?.tagName
    }

    /// What a request for the latest release came back with.
    enum Fetch: Equatable {
        /// A new answer: the release's tag, and the ETag that identifies this answer, if the server sent one.
        case release(tag: String, etag: String?)
        /// 304 Not Modified: the release is the one stored last time.
        case unchanged
        /// The request failed, or the answer was not a version.
        case failed
    }

    /// Reads the answer to a request for the latest release. A 304 counts as unchanged only when a tag is stored
    /// from an earlier answer, since that is the one it refers to.
    static func fetch(status: Int, etag: String?, data: Data, storedTag: String?) -> Fetch {
        switch status {
        case 304:
            return storedTag == nil ? .failed : .unchanged
        case 200:
            guard let tag = tag(inReleaseJSON: data), numbers(tag) != nil else { return .failed }
            return .release(tag: tag, etag: etag)
        default:
            return .failed
        }
    }

    /// The If-None-Match value for the next request. It is sent only with the tag stored alongside it, so a 304 always
    /// has a tag to answer with.
    static func conditionalETag(storedETag: String?, storedTag: String?) -> String? {
        guard let storedETag, !storedETag.isEmpty, storedTag != nil else { return nil }
        return storedETag
    }

    /// The version a menu item offers: the latest tag when it is newer than the current version, otherwise nil.
    static func availableVersion(latestTag: String?, current: String) -> String? {
        guard let latestTag, isNewer(latestTag, than: current) == true else { return nil }
        return latestTag
    }

    /// Automatic checks run once an hour while Library runs.
    static let automaticInterval: TimeInterval = 60 * 60

    /// Whether an automatic check is due: never checked, or the last check was an hour or more ago. A last check in the
    /// future (the clock was set back) counts as due, so a wrong clock cannot stop checks for long.
    static func automaticCheckIsDue(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= automaticInterval
    }

    /// The wait before the next automatic check: the rest of the hour since the last check, or none when it is due.
    static func secondsUntilAutomaticCheck(now: Date, lastCheck: Date?) -> TimeInterval {
        if automaticCheckIsDue(now: now, lastCheck: lastCheck) { return 0 }
        return automaticInterval - now.timeIntervalSince(lastCheck ?? now)
    }
}

/// The update the menu offers, shown at the top of the status menu like Software Update's item. Nil when the app is up
/// to date or no check has found a newer version.
@MainActor
final class UpdateStatus: ObservableObject {
    static let shared = UpdateStatus()

    @Published var availableVersion: String?
}

/// Checks GitHub for a newer release. Automatic checks run once an hour while Library runs, and on launch when the
/// last check was an hour or more ago. They are quiet: a newer version only adds an item to the top of the menu. A
/// check from Check for Updates… always answers with an alert.
@MainActor
enum UpdateCheck {
    /// The UserDefaults key of the "Check for updates automatically" setting. On by default, unless the user has
    /// chosen otherwise.
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    /// The ETag and tag of the last answer. The ETag makes the next request conditional, so GitHub answers 304 when
    /// nothing changed, and the tag stands in for that answer.
    private static let etagKey = "updateETag"
    private static let latestTagKey = "updateLatestTag"
    private static let repositoryURL = "https://github.com/deansasek/library.git"
    private static let latestURL = URL(string: "https://api.github.com/repos/deansasek/library/releases/latest")!
    private static let releasePage = URL(string: "https://github.com/deansasek/library/releases/latest")!
    private static var automaticTask: Task<Void, Never>?

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Registers the default for the setting. A value the user has already stored wins over the default.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [automaticKey: true])
    }

    /// Runs at launch: shows a version found by an earlier check, then starts the automatic checks.
    static func start() {
        let stored = UserDefaults.standard.string(forKey: latestTagKey)
        UpdateStatus.shared.availableVersion = UpdateRules.availableVersion(latestTag: stored, current: currentVersion)
        startAutomaticChecks()
    }

    /// Menu item. Always answers: up to date, a newer version, or that the check failed.
    static func checkNow() {
        Task {
            await check(interactive: true)
        }
    }

    /// The menu item's action: offers the version the menu shows.
    static func showAvailable() {
        guard let version = UpdateStatus.shared.availableVersion else { return }
        offer(version)
    }

    /// Starts the hourly automatic checks, or stops them when the setting is off. Checks at once when one is due.
    /// Called at launch and whenever the setting changes.
    static func startAutomaticChecks() {
        automaticTask?.cancel()
        automaticTask = nil
        guard UserDefaults.standard.bool(forKey: automaticKey) else { return }
        automaticTask = Task {
            while !Task.isCancelled, UserDefaults.standard.bool(forKey: automaticKey) {
                await check(interactive: false)
                let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
                let wait = UpdateRules.secondsUntilAutomaticCheck(now: .now, lastCheck: lastCheck)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// One request for the latest release. An automatic check that is not due does nothing.
    private static func check(interactive: Bool) async {
        if !interactive {
            let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
            guard UpdateRules.automaticCheckIsDue(now: .now, lastCheck: lastCheck) else { return }
        }
        UserDefaults.standard.set(Date.now, forKey: lastCheckKey)
        let fetch = await fetchLatest()
        apply(fetch, interactive: interactive)
    }

    /// Asks for the latest release, with the stored ETag when there is one.
    private static func fetchLatest() async -> UpdateRules.Fetch {
        let defaults = UserDefaults.standard
        let storedTag = defaults.string(forKey: latestTagKey)
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let session = URLSession(configuration: UpdateRules.sessionConfiguration())
        defer { session.finishTasksAndInvalidate() }
        request.setValue("Library/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = UpdateRules.conditionalETag(storedETag: defaults.string(forKey: etagKey), storedTag: storedTag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            let fetch = UpdateRules.fetch(status: http.statusCode, etag: http.value(forHTTPHeaderField: "ETag"),
                                          data: data, storedTag: storedTag)
            if case let .release(tag, etag) = fetch {
                defaults.set(tag, forKey: latestTagKey)
                defaults.set(etag, forKey: etagKey)
            }
            return fetch
        } catch {
            return .failed
        }
    }

    /// Updates the menu item from the answer. A failed check leaves the menu as it was. Only an interactive check
    /// shows an alert: an automatic one that finds a newer version just adds the menu item.
    private static func apply(_ fetch: UpdateRules.Fetch, interactive: Bool) {
        let tag: String?
        switch fetch {
        case let .release(latest, _):
            tag = latest
        case .unchanged:
            tag = UserDefaults.standard.string(forKey: latestTagKey)
        case .failed:
            if interactive {
                show(title: "Could Not Check for Updates",
                     message: "Library could not get the latest version from GitHub. Check your connection and try again.")
            }
            return
        }
        let version = UpdateRules.availableVersion(latestTag: tag, current: currentVersion)
        UpdateStatus.shared.availableVersion = version
        if let version {
            if interactive { offer(version) }
        } else if interactive {
            show(title: "Library Is Up to Date",
                 message: "Library \(currentVersion) is the latest version.")
        }
    }

    /// Offers the update. The first button downloads that release, builds it, installs it, and deletes the download,
    /// in Terminal, so no source copy is kept on the Mac.
    private static func offer(_ latestTag: String) {
        let title = "Library \(UpdateRules.displayVersion(latestTag)) Is Available"
        let response = show(title: title,
                            message: "You have Library \(currentVersion). Update in Terminal downloads this version, builds it, installs it in Applications, and removes the download afterward. Your library is kept.",
                            buttons: ["Update in Terminal", "Later"])
        if response == .alertFirstButtonReturn {
            runInTerminal(installCommand(tag: latestTag))
        }
    }

    /// Downloads one release into a temporary folder, runs its install script, and removes the folder whether or not
    /// the install succeeded.
    static func installCommand(tag: String) -> String {
        // The tag is already checked to be numeric. The zip and its SHA-256 are fetched from the same release, so the
        // checksum shows the download matches that release rather than that the release is genuine: it catches a
        // truncated or corrupt download, and anyone who can replace the release assets can replace both files.
        let version = String(tag.drop(while: { $0 == "v" }))
        let base = "https://github.com/deansasek/library/releases/download/\(tag)/Library-\(version)"
        return "T=\"$(mktemp -d)\" && cd \"$T\" && curl -fsSL -O \(shellQuoted(base + ".zip")) -O \(shellQuoted(base + ".zip.sha256")) "
            + "&& shasum -a 256 -c \(shellQuoted("Library-\(version).zip.sha256")) "
            + "&& unzip -q \(shellQuoted("Library-\(version).zip")) && \"./Library-\(version)/install.sh\"; cd /; rm -rf \"$T\""
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private static func show(title: String, message: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        return alert.runModal()
    }
}
