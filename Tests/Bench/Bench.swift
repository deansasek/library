import AppKit

// Timings for the hot paths on a synthetic library of 5,000 items. It prints numbers and never fails on them,
// so a slow machine cannot break the checks. Run it with ./test.sh.

/// 50 folders of 100 items: a mix of bookmarks, apps, commands, shortcuts, keywords, and color tags.
func syntheticLibrary(items: Int = 5_000) -> [LibraryItem] {
    let perFolder = 100
    return (0..<(items / perFolder)).map { folder in
        LibraryItem(name: "Folder \(folder)", children: (0..<perFolder).map { i in
            let index = folder * perFolder + i
            var node: LibraryItem
            if i % 10 == 0 {
                node = LibraryItem(name: "App \(index)", appPath: "/System/Library/CoreServices/Finder.app")
            } else if i % 3 == 0 {
                node = LibraryItem(name: "Command \(index)", command: "./run-\(index).sh --flag")
            } else {
                node = LibraryItem(name: "Site \(index)", url: "https://site\(index).example.com/path/\(index)")
            }
            node.keywords = "topic\(index % 40) team\(index % 9)"
            if i % 50 == 0 { node.shortcuts = [Shortcut(keyCode: UInt32(index % 26), modifiers: 256, key: "K")] }
            if i % 7 == 0 { node.color = "blue" }
            return node
        })
    }
}

/// Runs `body` `runs` times and prints the median time per run, in milliseconds.
func timeIt(_ label: String, runs: Int = 9, _ body: () -> Void) {
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        body()
        let elapsed = ContinuousClock.now - start
        samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "  %-52@ %9.3f ms", label as NSString, samples[samples.count / 2]))
}

@MainActor
func runBenchmark() {
    let library = syntheticLibrary()
    let leaves = library.leaves
    print("Benchmark: \(leaves.count) leaves in \(library.count) folders (median of 9 runs)")

    timeIt("walk leaves (icon pending list, Spotlight)") { _ = library.leaves }
    timeIt("per-edit hotkey layout, old code path") {
        _ = leaves.flatMap { node in
            (node.shortcuts ?? []).map { (node.id, $0) }
        }
    }
    timeIt("search filter, query \"topic7\" (matches many)") { _ = library.matching("topic7") }
    timeIt("search filter, query \"zzz\" (no match)") { _ = library.matching("zzz") }
    timeIt("search filter, empty query") { _ = library.matching("") }
    let cache = ManageListingCache()
    let listingKey = ManageListingCache.Key(query: "topic7", scope: .all, revision: 1, usage: 0, sort: .name, ascending: true)
    func listing() -> ManageListing {
        cache.listing(for: listingKey) {
            ManageListing.build(query: "topic7", scope: .all, nodes: library, deleted: [], sort: .name, ascending: true, counts: [:], opened: [:])
        }
    }
    timeIt("rows, sort by name (built)") {
        _ = ManageListing.build(query: "topic7", scope: .all, nodes: library, deleted: [], sort: .name, ascending: true, counts: [:], opened: [:])
    }
    _ = listing()
    timeIt("rows, same query and sort on a redraw (cached)") { _ = listing() }
    var renamed = library
    renamed[0].children![0].name = "Renamed"
    let before = TreeFingerprint(library)
    timeIt("fingerprint + both checks, rename") {
        let after = TreeFingerprint(renamed)
        _ = needsIconFetch(old: before, new: after)
        _ = needsHotKeyRegistration(old: before, new: after)
    }
    timeIt("fingerprint + both checks, shortcut edit") {
        var edited = library
        edited[0].children![0].shortcuts = [Shortcut(keyCode: 1, modifiers: 256, key: "S")]
        let after = TreeFingerprint(edited)
        _ = needsIconFetch(old: before, new: after)
        _ = needsHotKeyRegistration(old: before, new: after)
    }
    let finder = "/System/Library/CoreServices/Finder.app"
    timeIt("app icon, 5,000 redraw lookups") {
        for _ in 0..<5_000 { _ = appIcon(at: finder) }
    }
}
