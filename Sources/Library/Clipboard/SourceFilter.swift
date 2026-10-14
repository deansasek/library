import Foundation

/// "from <app>" in Quick Open: the clips copied while that app was in front. The rest of the query matches the text
/// as usual.
enum SourceFilter {
    struct Match: Equatable {
        /// The app's name as the history records it.
        let app: String
        /// The words after the app name. Empty when the query names only the app.
        let rest: String
    }

    /// The app named right after a leading "from", and the rest of the query. Nil when the query does not start with
    /// "from" followed by the name of one of `apps`, so "from" stays an ordinary word. Names are matched word by word,
    /// without regard to case, and the longest name wins, so "from google chrome" is not read as "google".
    static func parse(_ query: String, apps: [String]) -> Match? {
        let words = query.split(separator: " ")
        guard words.count >= 2, words[0].lowercased() == "from" else { return nil }
        let named = words.dropFirst()
        var best: (app: String, count: Int)?
        for app in apps {
            let appWords = app.split(separator: " ")
            guard !appWords.isEmpty, appWords.count <= named.count, best == nil || appWords.count > best!.count else { continue }
            if zip(appWords, named).allSatisfy({ $0.lowercased() == $1.lowercased() }) {
                best = (app, appWords.count)
            }
        }
        guard let best else { return nil }
        let rest = named.dropFirst(best.count).joined(separator: " ")
        return Match(app: best.app, rest: rest)
    }

    /// True when a clip copied while `source` was in front is one of the clips for `app`, without regard to case.
    static func includes(_ source: String?, app: String) -> Bool {
        source?.caseInsensitiveCompare(app) == .orderedSame
    }
}
