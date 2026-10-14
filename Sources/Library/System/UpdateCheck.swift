import AppKit

/// The parts of the update check that do not touch the network or the screen. Tested in Tests/Checks/main.swift.
enum UpdateRules {
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

    /// The `tag_name` of GitHub's latest-release response, or nil when the response has none.
    static func tag(inReleaseJSON data: Data) -> String? {
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        return (try? JSONDecoder().decode(Release.self, from: data))?.tagName
    }

    static let automaticInterval: TimeInterval = 24 * 60 * 60

    /// Whether an automatic check is due: never checked, or the last check was a day or more ago. A last check in the
    /// future (the clock was set back) counts as due, so a wrong clock cannot stop checks for long.
    static func automaticCheckIsDue(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= automaticInterval
    }
}

/// Checks GitHub for a newer release. It contacts api.github.com only when the user chooses Check for Updates, or
/// when Check for updates automatically is on (off by default) and a day has passed since the last check.
@MainActor
enum UpdateCheck {
    /// The UserDefaults key of the "Check for updates automatically" setting.
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    /// Written by install.sh: the clone that holds update.sh.
    private static let sourcePathKey = "sourcePath"
    private static let latestURL = URL(string: "https://api.github.com/repos/deansasek/library/releases/latest")!
    private static let releasePage = URL(string: "https://github.com/deansasek/library/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Menu item. Always answers: up to date, a newer version, or that the check failed.
    static func checkNow() {
        Task {
            let tag = await fetchLatestTag()
            present(latestTag: tag, interactive: true)
        }
    }

    /// Runs at launch. Checks at most once a day, and then shows an alert only when a newer version exists.
    /// It waits a few seconds so the alert does not appear over the launch windows.
    static func checkAutomaticallyIfDue() {
        guard UserDefaults.standard.bool(forKey: automaticKey) else { return }
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        guard UpdateRules.automaticCheckIsDue(now: .now, lastCheck: lastCheck) else { return }
        Task {
            try? await Task.sleep(for: .seconds(10))
            UserDefaults.standard.set(Date.now, forKey: lastCheckKey)
            let tag = await fetchLatestTag()
            present(latestTag: tag, interactive: false)
        }
    }

    /// The tag of the latest release, or nil when the request fails or the answer is not a version.
    private static func fetchLatestTag() async -> String? {
        var request = URLRequest(url: latestURL, timeoutInterval: 10)
        request.setValue("Library/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let tag = UpdateRules.tag(inReleaseJSON: data),
                  UpdateRules.numbers(tag) != nil
            else { return nil }
            return tag
        } catch {
            return nil
        }
    }

    private static func present(latestTag: String?, interactive: Bool) {
        guard let latestTag, let newer = UpdateRules.isNewer(latestTag, than: currentVersion) else {
            if interactive {
                show(title: "Could Not Check for Updates",
                     message: "Library could not get the latest version from GitHub. Check your connection and try again.")
            }
            return
        }
        if newer {
            offer(latestTag)
        } else if interactive {
            show(title: "Library Is Up to Date",
                 message: "Library \(currentVersion) is the latest version.")
        }
    }

    /// Offers the update. With a clone that holds update.sh, the first button runs it in Terminal. Otherwise the
    /// first button opens the release page.
    private static func offer(_ latestTag: String) {
        let title = "Library \(latestTag) Is Available"
        if let path = clonePath() {
            let response = show(title: title,
                                message: "You have Library \(currentVersion). Update in Terminal runs update.sh in your clone of Library. It pulls the new version and reinstalls it.",
                                buttons: ["Update in Terminal", "Later"])
            if response == .alertFirstButtonReturn {
                runInTerminal("cd \(shellQuoted(path)) && ./update.sh")
            }
        } else {
            let response = show(title: title,
                                message: "You have Library \(currentVersion). This copy was not installed from a clone of the repository, so update from the release page.",
                                buttons: ["View Release", "Later"])
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasePage)
            }
        }
    }

    /// The clone recorded by install.sh, if it still holds an executable update.sh.
    private static func clonePath() -> String? {
        guard let path = UserDefaults.standard.string(forKey: sourcePathKey),
              FileManager.default.isExecutableFile(atPath: path + "/update.sh")
        else { return nil }
        return path
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
