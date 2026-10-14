import Foundation

// Quick Open search benchmark. It prints timings and never fails.
// Run it from the repository root, compiling it with the app's sources (as test.sh does):
//
//   sources=(${(f)"$(find Sources/Library -name '*.swift' ! -name LibraryApp.swift)"})
//   swiftc -swift-version 6 -O $sources Tests/Bench/*.swift -o "${TMPDIR:-/tmp}/bench" && "${TMPDIR:-/tmp}/bench"
//
// Measures, at 5,000 items, over 9 runs:
//   - a full scan: the median of 20 queries that share no prefix with the previous one, so nothing can be reused,
//     per run, then the median of the 9 runs
//   - a keystroke: the median of the 180 keystrokes (20 per run, 9 runs) of a phrase typed one character at a time
//     into a fresh index, as the model does. The first keystroke of each run is a full scan.

enum QuickOpenBench {
    static let runs = 9
    static let itemCount = 5_000

    /// Deterministic library: folders of bookmarks and apps, with keywords, targets, and a few non-ASCII names.
    static func library() -> [LibraryItem] {
        let words = ["jira", "board", "build", "deploy", "kubernetes", "dashboard", "metrics", "logs", "staging",
                     "production", "docs", "wiki", "calendar", "mail", "notes", "design", "figma", "review", "ci",
                     "terminal", "xcode", "simulator", "budget", "invoice", "crm", "support", "tickets", "release"]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        var folders: [LibraryItem] = []
        var made = 0
        while made < itemCount {
            var children: [LibraryItem] = []
            for _ in 0..<50 where made < itemCount {
                let a = words[next(words.count)], b = words[next(words.count)]
                let suffix = next(10_000)
                let name = made % 97 == 0 ? "Café \(a) \(suffix)" : "\(a.capitalized) \(b) \(suffix)"
                let keywords = next(3) == 0 ? "\(b) \(words[next(words.count)])" : nil
                let item: LibraryItem
                switch next(3) {
                case 0: item = LibraryItem(name: name, url: "https://\(a).example.com/\(b)/\(suffix)", keywords: keywords)
                case 1: item = LibraryItem(name: name, command: "./\(a)-\(b).sh --env \(suffix)", keywords: keywords)
                default: item = LibraryItem(name: name, appPath: "/Applications/\(a.capitalized).app", keywords: keywords)
                }
                children.append(item)
                made += 1
            }
            folders.append(LibraryItem(name: "Folder \(folders.count)", children: children))
        }
        return folders
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    static func main() {
        let nodes = library()
        var counts: [String: Int] = [:]
        for (i, leaf) in nodes.flatMap(\.children!).enumerated() where i % 7 == 0 {
            counts[leaf.id.uuidString] = i % 5
        }
        var sink = 0

        // Full scan: alternate two queries that share no prefix, so each search starts over.
        let index = QuickOpenIndex(nodes: nodes)
        var scanTimes: [Double] = []
        for run in 0..<runs {
            var total: [Double] = []
            for step in 0..<20 {
                let query = (step + run) % 2 == 0 ? "zq" : "xv"
                let start = ContinuousClock.now
                sink &+= index.search(query, counts: counts).count
                total.append(ms(ContinuousClock.now - start))
            }
            scanTimes.append(median(total))
        }

        // Keystroke: a fresh index per run (built outside the timing), then a phrase typed one character at a time.
        let phrase = "kubernetes dashboard"
        var keyTimes: [Double] = []
        for _ in 0..<runs {
            let fresh = QuickOpenIndex(nodes: nodes)
            var typed = ""
            for character in phrase {
                typed.append(character)
                let start = ContinuousClock.now
                sink &+= fresh.search(typed, counts: counts).count
                keyTimes.append(ms(ContinuousClock.now - start))
            }
        }

        print("Quick Open benchmark, \(itemCount) items, median of \(runs) runs (ms per query)")
        print(String(format: "  full scan (no reusable prefix):      %.3f ms", median(scanTimes)))
        print(String(format: "  keystroke (typing \"%@\"):  %.3f ms", phrase, median(keyTimes)))
        print("  sink \(sink % 1)")
    }
}
