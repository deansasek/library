import Foundation

/// What the last link check found for a bookmark, and when it checked.
struct LinkStatus: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        /// The page answered with a success or redirect code.
        case ok
        /// The server answered with a client or server error code, such as 404 or 500.
        case broken
        /// No answer: a DNS failure, a refused connection, a timeout, or a redirect that could not be followed.
        case unreachable
        /// A value a newer version wrote. Decoding it does not fail the whole library; it is treated as not checked.
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    var kind: Kind
    var checked: Date
}

/// The rules of the link check: what a response means, which redirects to follow, and which bookmarks are due. No
/// network and no screen, so they are tested in Tests/Checks/main.swift.
enum LinkCheck {
    /// Each request waits this long for the server, the whole way through its redirects.
    static let timeout: TimeInterval = 10
    /// A request follows at most this many redirects.
    static let maxRedirects = 5
    /// At most this many addresses are requested at once.
    static let maxConcurrent = 4
    /// An address checked this recently is not requested again.
    static let recheckInterval: TimeInterval = 24 * 60 * 60
    /// The background check runs at most once in this interval.
    static let dailyInterval: TimeInterval = 24 * 60 * 60
    /// The most body bytes a GET reads, when a server refuses HEAD. The rest of the page is never downloaded.
    static let getBodyLimit = 64 * 1024

    /// The status for an HTTP status code. 2xx and 3xx are ok, 4xx and 5xx broken. Anything else is no usable answer.
    static func kind(forHTTPCode code: Int) -> LinkStatus.Kind {
        switch code {
        case 200..<400: return .ok
        case 400..<600: return .broken
        default: return .unreachable
        }
    }

    /// The status of a finished request. No response, or a redirect that was refused, is unreachable: the page never
    /// answered, so a 3xx that stopped a redirect loop does not count as a working page. This is the documented rule:
    /// a redirect loop, a redirect past `maxRedirects`, and a redirect to a non-web address are all unreachable.
    static func outcome(statusCode: Int?, redirectRefused: Bool) -> LinkStatus.Kind {
        guard let statusCode, !redirectRefused else { return .unreachable }
        return kind(forHTTPCode: statusCode)
    }

    /// Whether to follow a redirect to `target`, given how many redirects were already followed. Only web addresses
    /// are followed, and only up to `maxRedirects`.
    static func followsRedirect(after followed: Int, to target: URL?) -> Bool {
        followed < maxRedirects && target.map(WebFetch.isWeb) == true
    }

    /// Whether a HEAD answer means the server does not accept HEAD, so the check asks again with GET: 403, 405, or 501.
    /// Any other answer, or none, is final.
    static func retriesWithGET(afterHEAD statusCode: Int?) -> Bool {
        statusCode.map { [403, 405, 501].contains($0) } ?? false
    }

    /// True when `checked` is within the last 24 hours. A date in the future (the clock was set back) is not recent,
    /// so a wrong clock cannot stop checks for long.
    static func isRecentlyChecked(_ checked: Date?, now: Date) -> Bool {
        guard let checked else { return false }
        let elapsed = now.timeIntervalSince(checked)
        return elapsed >= 0 && elapsed < recheckInterval
    }

    /// Whether the background check is due: never run, or the last run was a day or more ago. A last run in the future
    /// counts as due, as it does for updates.
    static func isDailyCheckDue(now: Date, lastRun: Date?) -> Bool {
        guard let lastRun else { return true }
        let elapsed = now.timeIntervalSince(lastRun)
        return elapsed < 0 || elapsed >= dailyInterval
    }

    /// The wait until the next background check: none when one is due, else the rest of the day since the last run.
    static func secondsUntilDailyCheck(now: Date, lastRun: Date?) -> TimeInterval {
        guard !isDailyCheckDue(now: now, lastRun: lastRun), let lastRun else { return 0 }
        return dailyInterval - now.timeIntervalSince(lastRun)
    }

    /// True for a bookmark that has a web address to check: not a divider, folder, command, or application, and not a
    /// template, since its address is not complete until a value is typed.
    static func isCheckable(_ item: LibraryItem) -> Bool {
        guard item.isDivider != true, !item.isFolder, item.command == nil, item.appPath == nil,
              !item.isTemplate, let link = item.link else { return false }
        return WebFetch.isWeb(link)
    }

    /// The address a bookmark is checked at, as the key that groups bookmarks sharing one request.
    static func key(for item: LibraryItem) -> String? {
        item.link?.absoluteString
    }

    /// The checkable bookmarks that are due: every one whose address was not checked in the last 24 hours. An address
    /// is recent when any bookmark that uses it was checked, so the bookmarks sharing it are skipped together.
    static func itemsToCheck(_ items: [LibraryItem], now: Date) -> [LibraryItem] {
        let candidates = items.filter(isCheckable)
        let recent = Set(candidates.compactMap { item -> String? in
            isRecentlyChecked(item.linkStatus?.checked, now: now) ? key(for: item) : nil
        })
        return candidates.filter { item in key(for: item).map { !recent.contains($0) } ?? false }
    }

    /// How many requests to start now: enough to fill `maxConcurrent` slots, but no more than are waiting.
    static func startCount(running: Int, pending: Int) -> Int {
        min(max(0, maxConcurrent - running), max(0, pending))
    }
}
