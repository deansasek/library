import AppKit
import CryptoKit
import Carbon

var failures = 0
@MainActor func check(_ ok: Bool, _ what: String, line: Int = #line) { if !ok { failures += 1; print("FAIL line \(line): \(what)") } }

func tree() -> [LibraryItem] {
    [
        LibraryItem(name: "Apps", isDivider: true),
        LibraryItem(name: "Safari", appPath: "/Applications/Safari.app"),
        LibraryItem(name: "Work", children: [
            LibraryItem(name: "Jira", url: "tickets.example.com/browse/{}"),
            LibraryItem(name: "Deep", children: [LibraryItem(name: "Docs", url: "https://docs.example.com")]),
        ]),
    ]
}

// ---- model ----
check(splitArguments("--profile \"My Work\" -n 'a b'") == ["--profile", "My Work", "-n", "a b"], "quoted arguments")
let jira = LibraryItem(name: "Jira", url: "x.example.com/browse/{}")
check(jira.isTemplate && jira.link(filling: "ABC-123")?.absoluteString == "https://x.example.com/browse/ABC-123", "template fill")
check(jira.link(filling: "a b/c")?.absoluteString == "https://x.example.com/browse/a%20b%2Fc", "template encodes")

// ---- URL templates with named fields ----
check(templateFields(in: "x.example.com/{}") == [TemplateField(name: "", label: nil)], "bare placeholder is one unnamed field")
check(templateFields(in: "a/{}/{}") == [TemplateField(name: "", label: nil)], "repeated bare placeholder is one field")
check(templateFields(in: "a/{ticket:Ticket number}/{user}/{ticket}") == [
    TemplateField(name: "ticket", label: "Ticket number"), TemplateField(name: "user", label: nil),
], "named fields share a name and keep the first label")
check(templateFields(in: "a/{ticket}/{ticket:Later}").first?.label == "Later", "a label given later fills in a bare name")
check(templateFields(in: "a/{:Only label}").first == TemplateField(name: "", label: "Only label"), "a label without a name")
check(templateFields(in: "a/{ticket:}").first == TemplateField(name: "ticket", label: nil), "empty label is no label")
check(templateFields(in: "a/{open").isEmpty && templateFields(in: "a/{x{}").map(\.name) == [""], "unclosed braces are text")
check(!LibraryItem(name: "Plain", url: "a.example.com/{open").isTemplate && LibraryItem(name: "N", url: "a/{id}").isTemplate, "isTemplate for named fields")

let bug = LibraryItem(name: "Bug", url: "bugs.example.com/{project}/{id:Issue}?q={project}")
check(bug.placeholders.map(\.name) == ["project", "id"], "two fields, project shared")
check(bug.link(values: ["project": "WEB", "id": "12 3"])?.absoluteString == "https://bugs.example.com/WEB/12%203?q=WEB", "several values fill every placeholder")
check(bug.link(values: ["project": "WEB"]) == nil && bug.link(values: [:]) == nil, "a missing value is rejected")
check(bug.link(values: ["project": "a b/c", "id": "1"])?.absoluteString == "https://bugs.example.com/a%20b%2Fc/1?q=a%20b%2Fc", "named values encode the same way")
check(jira.link(values: ["": "ABC-123"])?.absoluteString == "https://x.example.com/browse/ABC-123", "bare value by its empty name")
check(bug.link(values: ["project": "", "id": ""])?.absoluteString == "https://bugs.example.com//?q=", "empty values still fill, the caller rejects them")
check(templatePreview("a/{id:Issue}/{}/{id}/{user}") == "a/‹Issue›/‹value›/‹Issue›/‹user›", "preview labels")
check(withoutPlaceholders("a/{}/{x:Y}/b") == "a///b", "placeholders removed")
check(LibraryItem(name: "Plain", url: "x.example.com/a").placeholders.isEmpty, "no placeholders for a plain URL")

// ---- Open All selection ----
let bulk: [LibraryItem] = [
    LibraryItem(name: "Divider", isDivider: true),
    LibraryItem(name: "Site", url: "https://a.example.com"),
    LibraryItem(name: "Ask", url: "https://b.example.com/{}"),
    LibraryItem(name: "Build", command: "make"),
    LibraryItem(name: "Gone", appPath: "/Applications/Missing.app"),
    LibraryItem(name: "Safari", appPath: "/Applications/Safari.app"),
    LibraryItem(name: "Inner", children: [
        LibraryItem(name: "Deep", url: "https://c.example.com"),
        LibraryItem(name: "Run", command: "./run.sh"),
        LibraryItem(name: "Blank", url: "   "),
    ]),
    LibraryItem(name: "Empty", children: []),
]
let selected = openAllSelection(in: bulk, appExists: { $0 != "/Applications/Missing.app" }).map(\.name)
check(selected == ["Site", "Safari", "Deep"], "open all keeps bookmarks and apps, skipping commands, templates, dividers, and missing apps: \(selected)")
check(openAllSelection(in: [LibraryItem(name: "Only", command: "make")]).isEmpty, "a folder of commands opens nothing")
check(!needsOpenAllConfirmation(5) && needsOpenAllConfirmation(6), "open all asks above five items")

var nodes = tree()
let docs = nodes.leaves.first { $0.name == "Docs" }!
check(nodes.removeNode(docs.id)?.name == "Docs" && nodes.node(withID: docs.id) == nil, "remove nested")
nodes = tree()
let deep = nodes.folders().first { $0.title == "Work / Deep" }!
nodes.append(LibraryItem(name: "New", url: "https://n.com"), to: deep.id)
check(nodes.leaves.map(\.name).contains("New"), "append into folder")
check(nodes.folders(skipping: [nodes.folders().first { $0.title == "Work" }!.id]).isEmpty, "skip subtree")
check(tree().sections.map(\.title) == ["Apps"], "sections")

var data = tree()
data[1].shortcuts = [Shortcut(keyCode: 17, modifiers: 256, key: "T", openNew: true)]
data[1].icon = "star.fill"; data[1].color = "red"; data[1].keywords = "term"; data[1].browser = "com.apple.Safari"
if let back = try? JSONDecoder().decode([LibraryItem].self, from: JSONEncoder().encode(data)) {
    check(back[1].shortcuts?.first?.description == "⌘T" && back[1].icon == "star.fill" && back[1].color == "red"
          && back[1].keywords == "term" && back[1].browser == "com.apple.Safari" && back[2].children?.count == 2, "JSON round trip")
} else { check(false, "decode") }

// ---- shortcuts ----
check(Shortcut(modifiers: UInt32(controlKey), button: 1).description == "⌃Right Click", "click description")
check(Shortcut(modifiers: 0, gesture: "cornerTopLeft").isCorner, "corner")
check(Shortcut.scrollName(dx: 0, dy: -5, inverted: true) == "scrollUp", "natural scroll up")
check(Shortcut(modifiers: 0).isEmpty, "empty shortcut")

// ---- custom icons ----
check(customIcon("star.fill") != nil && customIcon("🚀") != nil && customIcon("1") == nil, "icons")

// ---- Quick Open search ----
let pt = [LibraryItem(name: "Jira", url: "https://x.atlassian.net"),
          LibraryItem(name: "Work", children: [LibraryItem(name: "Jenkins", url: "https://ci.example.com")]),
          LibraryItem(name: "Terminal", appPath: "/System/Applications/Utilities/Terminal.app")]
check(QuickOpenResult.search("", in: pt, counts: [:]).compactMap(\.node).map(\.name) == ["Jira", "Jenkins", "Terminal"], "empty search order")
check(QuickOpenResult.search("j", in: pt, counts: [:]).compactMap(\.node).map(\.name) == ["Jira", "Jenkins"], "prefix search")
check(QuickOpenResult.link(from: "example.com/a")?.absoluteString == "https://example.com/a" && QuickOpenResult.link(from: "hello world") == nil, "link detection")

/// The Quick Open search as it was before the index: walks and lowercases the whole tree on every call. The index
/// must return exactly what this returns.
func referenceSearch(_ query: String, in nodes: [LibraryItem], counts: [String: Int]) -> [QuickOpenResult] {
    func flatten(_ nodes: [LibraryItem], folder: String) -> [QuickOpenResult] {
        nodes.flatMap { node -> [QuickOpenResult] in
            if let children = node.children {
                return flatten(children, folder: folder.isEmpty ? node.name : "\(folder) / \(node.name)")
            }
            return node.isOpenable ? [QuickOpenResult(kind: .item(node, folder: folder), id: node.id.uuidString)] : []
        }
    }
    func isSubsequence(_ word: String, of text: String) -> Bool {
        var remaining = word[...]
        for char in text where char == remaining.first { remaining = remaining.dropFirst() }
        return remaining.isEmpty
    }
    let words = query.lowercased().split(separator: " ").map(String.init)
    if words.isEmpty {
        return nodes.sections.flatMap { section -> [QuickOpenResult] in
            var items = flatten(section.nodes, folder: "")
            if !items.isEmpty { items[0].section = section.title ?? "Library" }
            return items
        }
    }
    let all = flatten(nodes, folder: "")
    let scored: [(result: QuickOpenResult, score: Int, index: Int)] = all.enumerated().compactMap { index, result in
        guard let node = result.node, case .item(_, let folder) = result.kind else { return nil }
        let name = node.name.lowercased()
        let keywords = "\(node.keywords ?? "") \(node.color ?? "")".lowercased().split(separator: " ").map(String.init)
        let other = "\(node.url ?? "") \(node.command ?? "") \(node.appPath ?? "") \(folder) \(keywords.joined(separator: " "))".lowercased()
        var total = 0
        for word in words {
            let score = name.hasPrefix(word) || keywords.contains(where: { $0.hasPrefix(word) }) ? 4
                : name.contains(word) ? 3 : isSubsequence(word, of: name) ? 1 : other.contains(word) ? 2 : 0
            if score == 0 { return nil }
            total += score
        }
        return (result, total, index)
    }
    return scored.sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        let (a, b) = (counts[$0.result.id] ?? 0, counts[$1.result.id] ?? 0)
        return a != b ? a > b : $0.index < $1.index
    }.map(\.result)
}
/// Results compared by identity, order, section, and title: everything Quick Open shows.
func keys(_ results: [QuickOpenResult]) -> [String] { results.map { "\($0.id)|\($0.section ?? "")|\($0.title)" } }

let qoLibrary: [LibraryItem] = [
    LibraryItem(name: "Apps", isDivider: true),
    LibraryItem(name: "Safari", appPath: "/Applications/Safari.app", keywords: "browser web"),
    LibraryItem(name: "Work", children: [
        LibraryItem(name: "Jira", url: "https://tickets.example.com/browse/{}", color: "blue"),
        LibraryItem(name: "Deep", children: [LibraryItem(name: "Docs", url: "https://docs.example.com")]),
        LibraryItem(name: "Jenkins", url: "https://ci.example.com"),
        LibraryItem(name: "Empty folder", children: []),
    ]),
    LibraryItem(name: "Tools", isDivider: true),
    LibraryItem(name: "Build", command: "make all", keywords: "compile release"),
    LibraryItem(name: "Deploy", command: "./deploy.sh --prod"),
    LibraryItem(name: "Terminal", appPath: "/System/Applications/Utilities/Terminal.app"),
]
let qoCounts = [qoLibrary.leaves.first { $0.name == "Jenkins" }!.id.uuidString: 3,
                qoLibrary.leaves.first { $0.name == "Docs" }!.id.uuidString: 3,
                qoLibrary.leaves.first { $0.name == "Safari" }!.id.uuidString: 1]
let qoQueries = ["", "  ", "j", "jira", "JIRA", "work", "docs", "example browse", "make", "release", "compile prod",
                 "blue", "web", "wrk", "trm", "zzz", "dep", "de", "a", "ap s", "app", "http", "tools", "ex", "jen"]
// One index, built once and searched for every query, as the model does.
let qoIndex = QuickOpenIndex(nodes: qoLibrary)
var qoMismatch: [String] = []
for query in qoQueries {
    for counts in [[String: Int](), qoCounts] where keys(qoIndex.search(query, counts: counts)) != keys(referenceSearch(query, in: qoLibrary, counts: counts)) {
        qoMismatch.append("\(query)|\(counts.isEmpty ? "no counts" : "counts")")
    }
}
check(qoMismatch.isEmpty, "index equals the uncached search: \(qoMismatch)")
check(qoIndex.search("", counts: [:]).first?.section == "Apps", "browse list starts with its divider")
// A new library gets a new index, and it finds what was added. The old index still answers for the old library.
var qoGrown = qoLibrary
qoGrown.append(LibraryItem(name: "Jiraffe", url: "https://zoo.example.com"))
check(QuickOpenIndex(nodes: qoGrown).search("jira", counts: [:]).map(\.title).contains("Jiraffe")
      && !qoIndex.search("jiraffe", counts: [:]).contains { $0.title == "Jiraffe" }, "a rebuilt index sees the change, the old one does not")
check(keys(QuickOpenIndex(nodes: qoGrown).search("jira", counts: [:])) == keys(referenceSearch("jira", in: qoGrown, counts: [:])), "rebuilt index equals the uncached search")
// A generated library with ASCII, non-ASCII, carriage-return, and Kelvin-sign text, so both the byte path and its
// String fallback run. One index per sequence: typing extends the previous query (the narrowing path), backspace
// and edits start over, and each query is checked against the uncached search, with and without counts.
var qoSeed: UInt64 = 42
@MainActor func qoNext(_ bound: Int) -> Int {
    qoSeed = qoSeed &* 6364136223846793005 &+ 1442695040888963407
    return Int((qoSeed >> 33) % UInt64(bound))
}
let qoPieces = ["jira", "Build", "café", "ÉTÉ", "Straße", "k", "docs", "a\r", "x y", "zz", "Ka\u{212A}", "example", "browse", "ci", "é"]
let qoBig: [LibraryItem] = (0..<8).map { folder in
    LibraryItem(name: "Folder \(folder)", children: (0..<40).map { _ in
        let name = (0..<(1 + qoNext(3))).map { _ in qoPieces[qoNext(qoPieces.count)] }.joined(separator: " ")
        let url = qoNext(2) == 0 ? "https://\(qoPieces[qoNext(qoPieces.count)]).example.com/\(qoNext(100))" : nil
        return LibraryItem(name: name, url: url, command: url == nil ? "run \(qoPieces[qoNext(qoPieces.count)])" : nil,
                           color: qoNext(4) == 0 ? "blue" : nil,
                           keywords: qoNext(3) == 0 ? qoPieces[qoNext(qoPieces.count)] : nil)
    })
}
let qoBigCounts = Dictionary(uniqueKeysWithValues: qoBig.leaves.prefix(60).enumerated().map { ($0.element.id.uuidString, $0.offset % 4) })
var qoBigMismatch: [String] = []
@MainActor func qoCompare(_ index: QuickOpenIndex, _ query: String) {
    for counts in [[String: Int](), qoBigCounts]
    where keys(index.search(query, counts: counts)) != keys(referenceSearch(query, in: qoBig, counts: counts)) {
        qoBigMismatch.append("\(query)|\(counts.isEmpty ? "no counts" : "counts")")
    }
}
let qoPhrases = qoBig.leaves.prefix(25).map(\.name) + ["Ka\u{212A}", "é", "ÉTÉ jira", "a\r b", "k", "x y z", "CAFÉ docs"]
for phrase in qoPhrases {
    let index = QuickOpenIndex(nodes: qoBig)
    var typed = ""
    var steps: [String] = []
    for character in phrase {
        typed.append(character)
        steps.append(typed)
    }
    steps += steps.dropLast().reversed()
    steps += ["", phrase, phrase + " ", phrase.uppercased(), phrase.lowercased() + "zz", phrase]
    for query in steps { qoCompare(index, query) }
}
let qoAlphabet = Array("jiraCbuoxkeésZ ".map(String.init))
for _ in 0..<20 {
    let index = QuickOpenIndex(nodes: qoBig)
    var query = ""
    for _ in 0..<60 {
        switch qoNext(4) {
        case 0 where !query.isEmpty: query.removeLast()
        case 1 where !query.isEmpty && qoNext(3) == 0: query.append(" ")
        default: query += qoAlphabet[qoNext(qoAlphabet.count)]
        }
        qoCompare(index, query)
    }
}
check(qoBigMismatch.isEmpty, "generated library: index equals the uncached search: \(qoBigMismatch.prefix(5))")
check(QuickOpenIndex(nodes: qoBig).search("e", counts: [:]).count > 20, "generated library has matches, so the equality checks are not vacuous")
// The debounce decision: a blank query recomputes at once, a typed one waits one frame. Coalescing itself
// (cancelling the pending recompute on each keystroke) is in QuickOpenModel.scheduleResults and is not run here.
check(QuickOpenModel.recomputeDelay(for: "") == nil && QuickOpenModel.recomputeDelay(for: "   ") == nil, "blank query recomputes at once")
check(QuickOpenModel.recomputeDelay(for: "j") == .milliseconds(16), "typed query waits one frame")

// ---- suggestions ----
let sel = AddSuggestion.make(selection: "https://swift.org/docs", clipboard: nil, in: tree())
check(sel?.source == .selection && sel?.node.name == "swift.org", "a selected link is suggested")
check(AddSuggestion.make(selection: "just some words", clipboard: nil, in: tree()) == nil, "plain selected text is not")
check(AddSuggestion.make(selection: "https://docs.example.com", clipboard: nil, in: tree()) == nil, "a link already in the library is not")
check(AddSuggestion.make(selection: nil, clipboard: nil, in: tree()) == nil, "nothing to suggest")

// ---- tracking parameters: a table of links and their cleaned copies ----
let trackingTable: [(link: String, clean: String)] = [
    ("https://example.com/a?utm_source=x&id=7", "https://example.com/a?id=7"),
    ("https://example.com/a?id=7&utm_medium=email&utm_campaign=spring", "https://example.com/a?id=7"),
    ("https://example.com/a?fbclid=abc", "https://example.com/a"),
    ("https://example.com/a?gclid=1&q=swift%20tips#section", "https://example.com/a?q=swift%20tips#section"),
    ("https://example.com/a?mc_eid=1&mc_cid=2", "https://example.com/a"),
    ("https://example.com/a?igshid=xyz", "https://example.com/a"),
    ("https://example.com/a?ref_src=twsrc%5Etfw", "https://example.com/a"),
    ("https://example.com/a?UTM_Source=x&FBCLID=2", "https://example.com/a"),
    ("https://example.com/a?utm_source=x#top", "https://example.com/a#top"),
    ("https://example.com/a?q=1&&utm_x=2", "https://example.com/a?q=1"),
    ("https://example.com/a?utm_source=x&utm_source=y", "https://example.com/a"),
    ("https://example.com/a?flag&utm_term", "https://example.com/a?flag"),
    ("https://example.com/a?ref=home&page=2", "https://example.com/a?ref=home&page=2"),
    ("https://example.com/a?utmsource=1&ref_srcs=2", "https://example.com/a?utmsource=1&ref_srcs=2"),
    ("https://example.com/a?keyword=utm_source&next=/x?fbclid=1", "https://example.com/a?keyword=utm_source&next=/x?fbclid=1"),
    ("https://example.com/a?id=7", "https://example.com/a?id=7"),
    ("https://example.com/a", "https://example.com/a"),
    ("https://example.com/a?", "https://example.com/a?"),
    ("https://example.com/a#x?utm_source=1", "https://example.com/a#x?utm_source=1"),
]
for row in trackingTable {
    check(TrackingParameters.clean(row.link) == row.clean, "cleaning \(row.link): got \(TrackingParameters.clean(row.link)), want \(row.clean)")
}
check(TrackingParameters.isTracking("utm_anything") && TrackingParameters.isTracking("GCLID") && !TrackingParameters.isTracking("ref"), "tracking names")
let trackingDefault = TrackingPreferences.shared.removesOnCopy
do {
    // A copied link is cleaned only when the setting is on. The history keeps the link as it was copied.
    let board = NSPasteboard(name: NSPasteboard.Name("library-checks-links-\(UUID().uuidString)"))
    let linkHistory = ClipboardHistory(pasteboard: board, file: nil, key: { throw ClipboardKey.KeychainError(status: -1) })
    let link = "https://example.com/a?utm_source=x&id=7"
    board.clearContents()
    board.setString(link, forType: .string)
    linkHistory.poll()
    let deadline = Date().addingTimeInterval(5)
    while linkHistory.pendingCaptures > 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    if let clip = linkHistory.items.first, clip.kind == .link {
        TrackingPreferences.shared.removesOnCopy = true
        linkHistory.copy(clip)
        check(board.string(forType: .string) == "https://example.com/a?id=7", "a copied link loses its tracking parameters when the setting is on")
        TrackingPreferences.shared.removesOnCopy = false
        linkHistory.copy(clip)
        check(board.string(forType: .string) == link, "with the setting off, a copied link is unchanged")
        check(clip.plainText == link, "the history keeps the link as it was copied")
    } else { check(false, "a copied link is recorded as a link") }
    TrackingPreferences.shared.removesOnCopy = trackingDefault
}
check(TrackingPreferences.shared.removesOnCopy == trackingDefault, "the tracking setting is restored")

// ---- snippets ----
let snippetList = [Snippet(name: "Home address", text: "1 Main St\nSpringfield", keywords: "street mailing")]
let snippetIndex = QuickOpenIndex(nodes: pt, snippets: snippetList)
check(snippetIndex.search("home", counts: [:]).map(\.title) == ["Home address"], "a snippet is found by name")
check(snippetIndex.search("mailing", counts: [:]).map(\.title) == ["Home address"], "a snippet is found by keyword")
check(snippetIndex.search("springfield", counts: [:]).isEmpty, "snippet text is not searched")
check(!snippetIndex.search("", counts: [:]).contains { $0.title == "Home address" }, "snippets are not in the browse list")
check(QuickOpenIndex(nodes: pt).search("home", counts: [:]).isEmpty, "without snippets, no snippet results")
if let found = snippetIndex.search("home", counts: [:]).first, case .snippet(let saved) = found.kind {
    check(saved.text.contains("Springfield"), "a snippet result carries its text")
} else { check(false, "a snippet result has the snippet kind") }
let snippetDir = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-snippets-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: snippetDir, withIntermediateDirectories: true)
let snippetFile = snippetDir.appendingPathComponent("snippets.json")
let savedSnippets = SnippetStore(file: snippetFile)
savedSnippets.add(Snippet(name: "Sig", text: "Thanks,\nDean"))
let reopenedSnippets = SnippetStore(file: snippetFile)
check(reopenedSnippets.snippets.map(\.name) == ["Sig"] && reopenedSnippets.snippets.first?.text == "Thanks,\nDean", "snippets reload from snippets.json")
check((try? Data(contentsOf: snippetFile))?.range(of: Data("Dean".utf8)) != nil, "snippets are plain text in snippets.json, not encrypted")
var renamedSnippet = savedSnippets.snippets[0]
renamedSnippet.name = "Signature"
savedSnippets.update(renamedSnippet)
check(SnippetStore(file: snippetFile).snippets.first?.name == "Signature", "an edit is saved")
savedSnippets.remove([renamedSnippet.id])
check(SnippetStore(file: snippetFile).snippets.isEmpty, "a delete is saved")
let damagedSnippetFile = snippetDir.appendingPathComponent("damaged-snippets.json")
try? Data("not a list".utf8).write(to: damagedSnippetFile)
let movedSnippets = SnippetStore(file: damagedSnippetFile)
check(movedSnippets.snippets.isEmpty && !FileManager.default.fileExists(atPath: damagedSnippetFile.path)
      && FileManager.default.fileExists(atPath: snippetDir.appendingPathComponent("snippets-damaged.json").path),
      "a damaged snippets file is moved aside, not read as snippets")
try? FileManager.default.removeItem(at: snippetDir)

// ---- a shortcut is equal to the same shortcut ----
check(Shortcut(modifiers: UInt32(controlKey), button: 1) == Shortcut(modifiers: UInt32(controlKey), button: 1), "shortcut equality")
check(Shortcut(modifiers: UInt32(controlKey), button: 1) != Shortcut(modifiers: UInt32(cmdKey), button: 1), "shortcut inequality")

// ---- a web page cannot run a terminal command through library://open ----
MainActor.assumeIsolated {
    let items = [
        LibraryItem(name: "Jira", url: "https://jira.example.com"),
        LibraryItem(name: "Deploy", command: "rm -rf ~/important"),
    ]
    check(AppDelegate.item(named: "jira", in: items)?.name == "Jira", "open a bookmark by name")
    check(AppDelegate.item(named: "Deploy", in: items) == nil, "a command is never opened by name")
}

// ---- Services: apps and folders dropped from Finder ----
MainActor.assumeIsolated {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("library-services-\(UUID().uuidString)")
    let fm = FileManager.default
    try? fm.createDirectory(at: base.appendingPathComponent("Notes"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: base.appendingPathComponent("Fake.app"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: base.appendingPathComponent("projects"), withIntermediateDirectories: true)
    try? Data().write(to: base.appendingPathComponent("readme.txt"))
    let notes = base.appendingPathComponent("Notes")
    let fake = base.appendingPathComponent("Fake.app")
    let text = base.appendingPathComponent("readme.txt")
    let web = URL(string: "https://example.com")!
    let existing = [
        LibraryItem(name: "Safari", appPath: "/Applications/Safari.app"),
        LibraryItem(name: "Work", children: [LibraryItem(name: "Projects", children: [])]),
        LibraryItem(name: "Notes", url: notes.standardizedFileURL.absoluteString, icon: "folder"),
    ]
    let (added, rejected) = AppDelegate.fileNodes(from: [
        URL(fileURLWithPath: "/Applications/Safari.app"),   // already in library
        fake,                                                // new app
        fake,                                                // repeated in the same drop
        notes,                                               // folder already linked in the library
        base.appendingPathComponent("projects"),             // new folder; a group with the same name does not block it
        text, web,                                           // unsupported
    ], existing: existing)
    check(added.map(\.name) == ["Fake", "projects"], "apps and folders added, duplicates skipped")
    check(added[0].appPath == fake.path && added[1].url?.hasPrefix("file:") == true && !added[1].isFolder, "app and folder shapes")
    check(added[1].link?.isFileURL == true && added[1].modeLabels == nil, "a folder link opens in Finder")
    check(rejected == [text, web], "files and links rejected")
    check(AppDelegate.fileNodes(from: [], existing: []).nodes.isEmpty, "nothing dropped, nothing added")
    try? fm.removeItem(at: base)
}

// ---- bookmarks.json: missing, unreadable, damaged, and readable files ----
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let bookmarks = folder.appendingPathComponent("bookmarks.json")
if case .missing = BookmarkFile.load(from: bookmarks) {} else { check(false, "a missing file is missing") }
try? Data("not json".utf8).write(to: bookmarks)
if case .damaged = BookmarkFile.load(from: bookmarks) {} else { check(false, "a file that is not a library is damaged") }
try? JSONEncoder().encode(tree()).write(to: bookmarks)
if case .loaded(let loaded) = BookmarkFile.load(from: bookmarks) { check(loaded.count == 3, "a readable file loads") } else { check(false, "a readable file loads") }
try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bookmarks.path)
if case .unreadable = BookmarkFile.load(from: bookmarks) {} else { check(false, "an unreadable file is reported, not replaced") }
try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bookmarks.path)
try? FileManager.default.removeItem(at: folder)

// ---- pinned clipboard file: sealing, migration, damage. A test key is used; the Keychain is never touched ----
do {
    let key = SymmetricKey(size: .bits256)
    let secret = Data("secret pinned text".utf8)
    if let sealed = try? PinnedFile.seal(secret, key: key) {
        check((try? PinnedFile.open(sealed, key: key)) == secret, "sealed bytes open with the same key")
        check(sealed.range(of: secret) == nil && sealed.range(of: Data("pinned".utf8)) == nil, "sealed bytes hide the text")
        check((try? PinnedFile.open(sealed, key: SymmetricKey(size: .bits256))) == nil, "a different key cannot open")
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0xFF
        if case .unreadable = PinnedFile.read(tampered, key: key) {} else { check(false, "a tampered file is rejected") }
        if case .unreadable = PinnedFile.read(sealed, key: nil) {} else { check(false, "a sealed file with no key is unreadable") }
    } else { check(false, "seal") }

    // A plain-text file from before encryption is read and marked for re-saving.
    let legacy = Data(#"[{"date":0,"source":"Notes","representations":[{"public.utf8-plain-text":"bGVnYWN5"}]}]"#.utf8)
    if case .clips(let clips, let migrated) = PinnedFile.read(legacy, key: key) {
        check(migrated && clips.count == 1 && clips[0].source == "Notes", "a plain-text file migrates")
    } else { check(false, "a plain-text file migrates") }
    let clip = PinnedFile.Clip(source: nil, date: Date(), representations: [["public.utf8-plain-text": Data("x".utf8)]])
    if let sealed = try? PinnedFile.encode([clip], key: key) {
        if case .clips(let clips, let migrated) = PinnedFile.read(sealed, key: key) {
            check(!migrated && clips.count == 1, "a sealed file reads without migrating")
        } else { check(false, "a sealed file reads") }
        check(sealed.range(of: Data("public.utf8-plain-text".utf8)) == nil, "the sealed file hides type names")
    } else { check(false, "encode") }

    // A damaged file is rejected without a crash.
    if case .unreadable = PinnedFile.read(Data(repeating: 0x41, count: 96), key: key) {} else { check(false, "a corrupt file is rejected") }
    if case .unreadable = PinnedFile.read(Data(), key: key) {} else { check(false, "an empty file is rejected") }
}

// ---- clipboard history and menu, on a private pasteboard ----
MainActor.assumeIsolated {
    let testKey = SymmetricKey(size: .bits256)
    // The pinned file is read in the background, so a check waits until the history has published its pins.
    @MainActor func waitForLoad(_ loading: ClipboardHistory) {
        let deadline = Date().addingTimeInterval(5)
        while !loading.pinnedLoaded, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    let board = NSPasteboard(name: NSPasteboard.Name("library-checks-\(UUID().uuidString)"))
    let saveFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-\(UUID().uuidString).json")
    let history = ClipboardHistory(pasteboard: board, file: saveFile, key: { testKey })
    waitForLoad(history)

    // A plain-text pinned file from before encryption is migrated on load, leaving no plain text behind.
    let legacyFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-legacy-\(UUID().uuidString).json")
    let legacy = [PinnedFile.Clip(source: "Notes", date: Date(), representations: [["public.utf8-plain-text": Data("legacy pin".utf8)]])]
    try? JSONEncoder().encode(legacy).write(to: legacyFile)
    let migrated = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-m-\(UUID().uuidString)")), file: legacyFile, key: { testKey })
    waitForLoad(migrated)
    ClipboardHistory.waitForSaves()
    check(migrated.items.map(\.title) == ["legacy pin"] && migrated.items.first?.pinned == true, "a plain-text file loads its pins")
    let migratedBytes = (try? Data(contentsOf: legacyFile)) ?? Data()
    check(migratedBytes.range(of: Data("legacy pin".utf8)) == nil, "a migrated file hides the text")
    if case .clips(_, let migratedAgain) = PinnedFile.read(migratedBytes, key: testKey) {
        check(!migratedAgain, "a migrated file is sealed with the key")
    } else { check(false, "a migrated file reads back") }
    try? FileManager.default.removeItem(at: legacyFile)

    // A damaged pinned file is moved aside, and the history starts with no pins.
    let damagedFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-damaged-\(UUID().uuidString).json")
    try? Data(repeating: 0x42, count: 80).write(to: damagedFile)
    let damagedHistory = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-d-\(UUID().uuidString)")), file: damagedFile, key: { testKey })
    let movedAside = damagedFile.deletingLastPathComponent().appendingPathComponent("clipboard-damaged.bin")
    waitForLoad(damagedHistory)
    check(damagedHistory.items.isEmpty && !FileManager.default.fileExists(atPath: damagedFile.path) && FileManager.default.fileExists(atPath: movedAside.path), "a damaged file is kept aside")
    try? FileManager.default.removeItem(at: movedAside)

    // With no key, a sealed file is neither moved nor overwritten.
    let lockedFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-locked-\(UUID().uuidString).json")
    let sealedBytes = (try? PinnedFile.encode(legacy, key: testKey)) ?? Data()
    try? sealedBytes.write(to: lockedFile)
    let locked = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-l-\(UUID().uuidString)")), file: lockedFile, key: { throw ClipboardKey.KeychainError(status: -1) })
    waitForLoad(locked)
    check(locked.items.isEmpty && (try? Data(contentsOf: lockedFile)) == sealedBytes, "no key leaves the sealed file untouched")
    try? FileManager.default.removeItem(at: lockedFile)

    // Copies are built in the background, so a check waits until the history has added them.
    @MainActor func settle() {
        let deadline = Date().addingTimeInterval(5)
        while history.pendingCaptures > 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    // A copy made while the pinned file is still loading is kept. The loaded pins merge in after the newer copies,
    // a pin whose copy was made again is not added twice, and nothing is written over the file until it has loaded.
    let mergeFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-merge-\(UUID().uuidString).json")
    let seedBoard = NSPasteboard(name: NSPasteboard.Name("library-checks-seed-\(UUID().uuidString)"))
    let seed = ClipboardHistory(pasteboard: seedBoard, file: mergeFile, key: { testKey })
    waitForLoad(seed)
    @MainActor func copyText(_ text: String, on pasteboard: NSPasteboard, into target: ClipboardHistory) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        pasteboard.writeObjects([item])
        target.poll()
        let deadline = Date().addingTimeInterval(5)
        while target.pendingCaptures > 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    copyText("pinned one", on: seedBoard, into: seed)
    copyText("pinned two", on: seedBoard, into: seed)
    seed.togglePin(seed.items[0])
    seed.togglePin(seed.items[1])
    ClipboardHistory.waitForSaves()
    let gate = DispatchSemaphore(value: 0)
    let mergeBoard = NSPasteboard(name: NSPasteboard.Name("library-checks-merge-\(UUID().uuidString)"))
    // The first caller waits for the gate, then the gate is opened again for later callers, as the Keychain key would be.
    let merging = ClipboardHistory(pasteboard: mergeBoard, file: mergeFile, key: { gate.wait(); gate.signal(); return testKey })
    check(!merging.pinnedLoaded, "the pinned file waits for its key")
    copyText("pinned two", on: mergeBoard, into: merging)
    copyText("fresh copy", on: mergeBoard, into: merging)
    check(merging.items.map(\.title) == ["fresh copy", "pinned two"] && merging.items.allSatisfy { !$0.pinned }, "copies made during the load are kept")
    let beforeLoad = (try? Data(contentsOf: mergeFile)) ?? Data()
    merging.togglePin(merging.items[0])
    ClipboardHistory.waitForSaves()
    check((try? Data(contentsOf: mergeFile)) == beforeLoad, "nothing is written before the pinned file has loaded")
    gate.signal()
    waitForLoad(merging)
    check(merging.items.map(\.title) == ["fresh copy", "pinned two", "pinned one"], "loaded pins follow the newer copies, a repeat is merged")
    check(merging.items.allSatisfy(\.pinned), "pins are kept after the merge")
    check(zip(merging.items, merging.items.dropFirst()).allSatisfy { $0.date >= $1.date }, "merged order is newest first")
    check(Set(merging.items.map(\.digest)).count == merging.items.count, "no item appears twice")
    ClipboardHistory.waitForSaves()
    if case .clips(let saved, _) = PinnedFile.read((try? Data(contentsOf: mergeFile)) ?? Data(), key: testKey) {
        check(saved.count == 3, "the merged pins are saved")
    } else { check(false, "the merged pins are saved") }
    try? FileManager.default.removeItem(at: mergeFile)

    @MainActor func copy(_ text: String, extra: [String: Data] = [:]) {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        extra.forEach { item.setData($1, forType: NSPasteboard.PasteboardType($0)) }
        board.writeObjects([item])
        history.poll()
        settle()
    }

    copy("first copy"); copy("https://example.com/page"); copy("line one\n   line  two")
    check(history.items.map(\.title) == ["line one", "https://example.com/page", "first copy"], "newest first, one-line titles")
    check(history.items[1].kind == .link, "link kind")
    copy("first copy")
    check(history.items.count == 3 && history.items[0].title == "first copy", "a repeat moves to the top")
    history.togglePin(history.items[2])
    ClipboardHistory.waitForSaves()
    check(FileManager.default.fileExists(atPath: saveFile.path), "pinning saves the file")
    check(((try? FileManager.default.attributesOfItem(atPath: saveFile.path))?[.posixPermissions] as? Int) == 0o600, "private file")
    let pinnedBytes = (try? Data(contentsOf: saveFile)) ?? Data()
    check((try? JSONDecoder().decode([PinnedFile.Clip].self, from: pinnedBytes)) == nil, "the pinned file is not plain JSON")
    if let pinnedText = history.items.first(where: \.pinned)?.plainText {
        check(pinnedBytes.range(of: Data(pinnedText.utf8)) == nil, "the pinned file hides the pinned text")
    } else { check(false, "an item is pinned") }
    let reloaded = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-2-\(UUID().uuidString)")), file: saveFile, key: { testKey })
    waitForLoad(reloaded)
    check(reloaded.items.count == history.items.filter(\.pinned).count, "pinned items reload")
    copy("secret", extra: ["org.nspasteboard.ConcealedType": Data()])
    check(!history.items.contains { $0.title == "secret" }, "private copies skipped")
    check(history.search("example").count == 1, "search")
    check(history.search("example line").isEmpty && history.search("line two").count == 1, "search needs every word")
    check(history.items.first { $0.kind == .link }?.searchText == "https://example.com/page https://example.com/page", "search text is lowercased title and text")
    copy("web image", extra: ["public.html": Data(#"<img src="https://media.example.com/clips/party.gif?w=2">"#.utf8)])
    check(history.items[0].gifURL?.path == "/clips/party.gif", "GIF address in HTML")
    copy("web", extra: ["public.html": Data(#"<img src="file:///tmp/secret.gif">"#.utf8)])
    check(history.items[0].gifURL == nil, "only web addresses")
    for index in 0..<60 { copy("filler \(index)") }
    check(history.items.filter { !$0.pinned }.count <= 50 && history.items.contains { $0.pinned }, "trimmed to 50, pins kept")
    history.clear()
    check(history.items.allSatisfy(\.pinned), "clear keeps pins")
    history.remove(history.items[0])
    ClipboardHistory.waitForSaves()
    check(history.items.isEmpty && !FileManager.default.fileExists(atPath: saveFile.path), "removing the last pin removes the file")

    for index in 1...12 { copy("menu copy \(index)") }
    let (menu, target) = PopupMenu.makeClipboardMenu(history: history, suggestion: nil, pastes: false)
    let numbered = menu.items.filter { !$0.keyEquivalent.isEmpty && $0.keyEquivalentModifierMask.isEmpty }
    check(numbered.map(\.keyEquivalent) == (1...9).map(String.init), "number keys 1 to 9")
    check(menu.items.filter(\.isSectionHeader).map(\.title) == ["Recent"], "copy header")
    let (pasteMenu, pasteTarget) = PopupMenu.makeClipboardMenu(history: history, suggestion: nil, pastes: true)
    check(pasteMenu.items.filter(\.isSectionHeader).map(\.title) == ["Paste Recent"], "paste header")
    let node = LibraryItem(name: "docs.example.com", url: "https://docs.example.com")
    let (withAdd, addTarget) = PopupMenu.makeClipboardMenu(history: history, suggestion: AddSuggestion(node: node, source: .selection), pastes: false)
    check(withAdd.items.first?.title == "Add “docs.example.com” to Library", "suggestion first")
    _ = (target, pasteTarget, addTarget)
}

// ---- Quick Look sources ----
func clip(_ kind: ClipItem.Kind, text: String? = nil, files: [URL] = [], reps: [[NSPasteboard.PasteboardType: Data]] = [],
          link: URL? = nil, animated: Data? = nil) -> ClipItem {
    ClipItem(representations: reps, digest: UUID().uuidString, kind: kind, title: "clip", plainText: text, link: link,
             thumbnail: nil, gifURL: nil, fileURLs: files, byteCount: 0, animatedData: animated)
}
let previewDir = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-preview-\(UUID().uuidString)")
let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = pixels.representation(using: .png, properties: [:])!
let tiff = pixels.tiffRepresentation!
let gifBytes = Data("GIF89a".utf8)

if let url = ClipPreviewSource.url(for: clip(.text, text: "hello there"), in: previewDir) {
    check(url.pathExtension == "txt" && url.deletingLastPathComponent().path == previewDir.path, "text goes to a .txt in the folder")
    check((try? String(contentsOf: url, encoding: .utf8)) == "hello there", "text written as is")
} else { check(false, "text preview file") }
if let url = ClipPreviewSource.url(for: clip(.link, text: "https://example.com", link: URL(string: "https://example.com")), in: previewDir) {
    check(url.pathExtension == "txt" && (try? String(contentsOf: url, encoding: .utf8)) == "https://example.com", "link written as text")
} else { check(false, "link preview file") }
check(ClipPreviewSource.url(for: clip(.other), in: previewDir) == nil, "nothing to preview for other items")
let filePath = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
check(ClipPreviewSource.url(for: clip(.file, files: [filePath, URL(fileURLWithPath: "/tmp/b.txt")]), in: previewDir) == filePath,
      "file previews its first file in place")
if let url = ClipPreviewSource.url(for: clip(.image, reps: [[.png: png]]), in: previewDir) {
    check(url.pathExtension == "png" && (try? Data(contentsOf: url)) == png, "PNG picture written with a .png name")
} else { check(false, "png preview file") }
if let url = ClipPreviewSource.url(for: clip(.image, reps: [[.tiff: tiff]]), in: previewDir) {
    check(url.pathExtension == "tiff" && (try? Data(contentsOf: url)) == tiff, "TIFF picture written with a .tiff name")
} else { check(false, "tiff preview file") }
let gifFile = URL(fileURLWithPath: "/tmp/party.gif")
check(ClipPreviewSource.url(for: clip(.file, files: [gifFile]), in: previewDir) == gifFile, "GIF file previews in place")
if let url = ClipPreviewSource.url(for: clip(.image, reps: [[ClipItem.gifType: gifBytes]]), in: previewDir) {
    check(url.pathExtension == "gif" && (try? Data(contentsOf: url)) == gifBytes, "GIF data written with a .gif name")
} else { check(false, "gif preview file") }
try? FileManager.default.removeItem(at: previewDir)
// ---- bookmark import ----
let safariPlist = Data("""
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
<key>WebBookmarkType</key><string>WebBookmarkTypeList</string>
<key>Children</key>
<array>
  <dict>
    <key>Title</key><string>BookmarksBar</string>
    <key>WebBookmarkType</key><string>WebBookmarkTypeList</string>
    <key>Children</key>
    <array>
      <dict>
        <key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string>
        <key>URLString</key><string>https://swift.org</string>
        <key>URIDictionary</key><dict><key>title</key><string>Swift</string></dict>
      </dict>
      <dict>
        <key>Title</key><string>Work</string>
        <key>WebBookmarkType</key><string>WebBookmarkTypeList</string>
        <key>Children</key>
        <array>
          <dict>
            <key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string>
            <key>URLString</key><string>https://docs.example.com</string>
            <key>URIDictionary</key><dict><key>title</key><string>Docs</string></dict>
          </dict>
          <dict>
            <key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string>
            <key>URLString</key><string>file:///etc/hosts</string>
            <key>URIDictionary</key><dict><key>title</key><string>Local</string></dict>
          </dict>
        </array>
      </dict>
    </array>
  </dict>
  <dict>
    <key>Title</key><string>com.apple.ReadingList</string>
    <key>WebBookmarkType</key><string>WebBookmarkTypeList</string>
    <key>Children</key>
    <array>
      <dict>
        <key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string>
        <key>URLString</key><string>https://reading.example.com</string>
        <key>URIDictionary</key><dict><key>title</key><string>Later</string></dict>
      </dict>
    </array>
  </dict>
</array>
</dict>
</plist>
""".utf8)

let chromeJSON = Data("""
{"checksum": "x", "version": 1, "roots": {
  "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
    {"type": "url", "name": "GitHub", "url": "https://github.com"},
    {"type": "folder", "name": "Work", "children": [
      {"type": "url", "name": "Docs", "url": "https://docs.example.com"},
      {"type": "url", "name": "Script", "url": "javascript:alert(1)"},
      {"type": "folder", "name": "Empty", "children": []}
    ]}
  ]},
  "other": {"type": "folder", "name": "Other bookmarks", "children": []},
  "synced": {"type": "folder", "name": "Mobile bookmarks", "children": [
    {"type": "url", "name": "Phone", "url": "https://m.example.com"}
  ]}
}}
""".utf8)

if let safari = try? BookmarkImport.parse(safariPlist) {
    check(safari.browser == .safari && safari.folder.name == "Imported from Safari", "safari folder name")
    check(safari.imported == 2 && safari.skipped == 1, "safari counts skip file links and Reading List")
    let bar = safari.folder.children?.first
    check(bar?.name == "Favorites Bar" && bar?.children?.map(\.name) == ["Swift", "Work"], "safari mirrors folders")
    check(bar?.children?.last?.children?.map(\.url) == ["https://docs.example.com"], "safari nested bookmark")
} else { check(false, "safari parse") }

if let chrome = try? BookmarkImport.parse(chromeJSON) {
    check(chrome.browser == .chrome && chrome.folder.name == "Imported from Chrome", "chrome folder name")
    check(chrome.imported == 3 && chrome.skipped == 1, "chrome counts skip javascript links")
    check(chrome.folder.children?.map(\.name) == ["Bookmarks bar", "Mobile bookmarks"], "chrome drops empty roots")
    let work = chrome.folder.children?.first?.children?.first { $0.name == "Work" }
    check(work?.children?.map(\.name) == ["Docs"], "chrome nested folder drops empty folder")
} else { check(false, "chrome parse") }

for bad in ["", "{\"roots\": {", "not a bookmarks file", "<plist version=\"1.0\"><dict><key>a</key><string>b</string></dict></plist>"] {
    check((try? BookmarkImport.parse(Data(bad.utf8))) == nil, "rejects \"\(bad)\"")
}
check((try? BookmarkImport.parse(safariPlist.prefix(300))) == nil, "rejects truncated plist")
check((try? BookmarkImport.parse(chromeJSON.prefix(120))) == nil, "rejects truncated JSON")
// ---- Library window search ----
let searchTree = tree() + [LibraryItem(name: "Build", command: "make all", keywords: "compile release")]
check(searchTree.matching("") .allIDs == searchTree.allIDs, "empty search keeps the tree")
check(searchTree.matching("   ").allIDs == searchTree.allIDs, "blank search keeps the tree")
check(searchTree.matching("jira").leaves.map(\.name) == ["Jira"], "search by name")
check(searchTree.matching("SAFARI").leaves.map(\.name) == ["Safari"], "search ignores case")
check(searchTree.matching("example browse").leaves.map(\.name) == ["Jira"], "every word must match")
check(searchTree.matching("docs").leaves.map(\.name) == ["Docs"], "search by URL")
check(searchTree.matching("docs").folders().map(\.title) == ["Work", "Work / Deep"], "search keeps folders of matches")
check(searchTree.matching("make").leaves.map(\.name) == ["Build"], "search by command")
check(searchTree.matching("release").leaves.map(\.name) == ["Build"], "search by keywords")
check(searchTree.matching("apps").isEmpty, "dividers do not match")
check(searchTree.matching("work").leaves.map(\.name) == ["Jira", "Docs"], "folder name match keeps contents")
check(searchTree.matching("zzz").isEmpty, "no match is empty")
// ---- Work after an edit: renames do no icon or hot key work ----
let fpTree = tree()
let fpBase = TreeFingerprint(fpTree)
var fpRenamed = fpTree; fpRenamed[1].name = "Firefox"; fpRenamed[2].children![0].name = "Jira 2"; fpRenamed[2].name = "Projects"
check(!needsIconFetch(old: fpBase, new: TreeFingerprint(fpRenamed)) && !needsHotKeyRegistration(old: fpBase, new: TreeFingerprint(fpRenamed)), "renames alone do no follow-up work")
var fpURL = fpTree; fpURL[1].url = "https://new.example.com"
check(needsIconFetch(old: fpBase, new: TreeFingerprint(fpURL)) && !needsHotKeyRegistration(old: fpBase, new: TreeFingerprint(fpURL)), "a URL change fetches icons, not hot keys")
var fpKeywords = fpTree; fpKeywords[1].keywords = "browser"
check(needsIconFetch(old: fpBase, new: TreeFingerprint(fpKeywords)), "a keyword change counts as a change")
var fpShortcut = fpTree; fpShortcut[1].shortcuts = [Shortcut(keyCode: 1, modifiers: 256, key: "S")]
check(needsHotKeyRegistration(old: fpBase, new: TreeFingerprint(fpShortcut)), "a shortcut change registers hot keys")
var fpMoved = fpTree; fpMoved.swapAt(1, 2)
check(needsIconFetch(old: fpBase, new: TreeFingerprint(fpMoved)), "a move counts as a change")
var fpAdded = fpTree; fpAdded.append(LibraryItem(name: "New", url: "https://n.example.com"))
check(needsIconFetch(old: fpBase, new: TreeFingerprint(fpAdded)), "an addition counts as a change")
check(TreeFingerprint(fpShortcut).bindings.count == 1 && fpBase.bindings.isEmpty, "bindings list shortcuts of items only")

// ---- Icon modification dates: read from disk at most once in five seconds ----
let dateCache = ModificationDateCache()
var dateReads = 0
let readDate: () -> Date? = { dateReads += 1; return Date(timeIntervalSince1970: Double(dateReads)) }
_ = dateCache.modified(at: "/a.app", now: 0, read: readDate)
check(dateCache.modified(at: "/a.app", now: 4_000_000_000, read: readDate) == Date(timeIntervalSince1970: 1) && dateReads == 1, "a date is not read again within five seconds")
_ = dateCache.modified(at: "/a.app", now: 5_000_000_001, read: readDate)
check(dateReads == 2, "a date is read again after five seconds")
_ = dateCache.modified(at: "/b.app", now: 5_000_000_001, read: readDate)
check(dateReads == 3, "each path has its own date")

// ---- Search result kept between redraws ----
let searchCache = SearchCache()
let searchedTree = tree()
check(searchCache.result(for: "jira", revision: 1, in: searchedTree).count == 1, "cached search counts bookmarks")
check(searchCache.result(for: "jira", revision: 1, in: []).count == 1, "same query and library reuse the search")
check(searchCache.result(for: "jira", revision: 2, in: []).count == 0, "a changed library searches again")
check(searchCache.result(for: "docs", revision: 2, in: searchedTree).tree.leaves.map(\.name) == ["Docs"], "a changed query searches again")

// ---- App Intents logic: no Shortcuts needed ----
let intentNodes = [
    LibraryItem(name: "Jira", url: "https://jira.example.com"),
    LibraryItem(name: "Deploy", command: "./deploy.sh --prod"),
    LibraryItem(name: "Blank", command: "   "),
    LibraryItem(name: "Safari", appPath: "/Applications/Safari.app"),
]
check(IntentLogic.launchables(matching: "", in: intentNodes, counts: [:]).map(\.name) == ["Jira", "Safari"], "intents list bookmarks and apps, not commands")
check(IntentLogic.launchables(matching: "deploy", in: intentNodes, counts: [:]).isEmpty, "a command is never found by search")
check(IntentLogic.launchables(matching: "jira", in: intentNodes, counts: [:]).map(\.name) == ["Jira"], "search finds a bookmark")
check(IntentLogic.commands(in: intentNodes).map(\.name) == ["Deploy"], "only commands with text are runnable")
check(!IntentLogic.canRunCommand(intentNodes[0]) && !IntentLogic.canRunCommand(intentNodes[2]) && IntentLogic.canRunCommand(intentNodes[1]), "command rule")
check(IntentLogic.confirmation(for: intentNodes[1]).contains("./deploy.sh --prod"), "confirmation names the command")
check(IntentLogic.bookmark(from: "docs.example.com/a")?.url == "https://docs.example.com/a" && IntentLogic.bookmark(from: "docs.example.com/a")?.name == "docs.example.com", "bookmark from a link")
check(IntentLogic.bookmark(from: "hello world") == nil, "text is not a bookmark")
check(IntentLogic.app(atPath: "/Applications/Safari.app")?.appPath == "/Applications/Safari.app" && IntentLogic.app(atPath: "/Applications/Safari.app")?.name == "Safari", "app from a bundle")
check(IntentLogic.app(atPath: "/tmp/notes.txt") == nil, "a non-app file is not an app")

// ---- favicon limits and failure memory (pure; no network or defaults) ----
let nowStamp: TimeInterval = 1_800_000_000
let kept = Favicon.pruned([
    "recent.example.com": nowStamp - 3600,
    "old.example.com": nowStamp - Favicon.failureWindow - 1,
    "future.example.com": nowStamp + 100,
], now: nowStamp)
check(Array(kept.keys) == ["recent.example.com"], "failures expire after 24 h and future stamps are dropped")
check(Favicon.failureWindow == 24 * 60 * 60, "failure window is 24 h")

// ---- stale Terminal command files (pure; no files touched) ----
let commandNow = Date(timeIntervalSince1970: nowStamp)
let commandFiles: [(name: String, modified: Date)] = [
    ("library-old.command", commandNow.addingTimeInterval(-3601)),
    ("library-fresh.command", commandNow.addingTimeInterval(-600)),
    ("library-edge.command", commandNow.addingTimeInterval(-3600)),
    ("other-old.command", commandNow.addingTimeInterval(-7200)),
    ("library-old.txt", commandNow.addingTimeInterval(-7200)),
]
check(staleCommandFiles(among: commandFiles, now: commandNow) == ["library-old.command"], "only old library command files are stale")
// ---- SF Symbols: every name the app asks for resolves ----
// The scan reads the app's Swift files, so a symbol added or renamed in source is checked without editing this file.
// Names the code builds at runtime (no string literal in the argument) are listed below with the reason they are safe.
let runtimeSymbolUses: [(file: String, expression: String, reason: String)] = [
    ("Model/Icons.swift", "text", "a custom icon the user typed; customIcon returns nil for an unknown name"),
    ("Model/LibraryStore.swift", "name", "private symbol(_:) helper; its literal callers are read by the symbol(\"...\") rule"),
    ("QuickOpen/QuickOpenModel.swift", "name", "private symbol(_:) helper; its literal callers are read by the symbol(\"...\") rule"),
    ("Manage/ManageState.swift", "$0", "the saved icon of an item, only tested to choose the picker tab"),
    ("Manage/IconPicker.swift", "$0", "filters the symbols list below, so only names that resolve are shown"),
    ("Manage/IconPicker.swift", "name", "a name from the symbols list below, which the list's own filter has already checked"),
    ("Welcome/WelcomeView.swift", "symbol", "passed in from icon, feature and shortcutRow calls; their literals are read by the Welcome rule"),
]
let swiftRoot = "Sources/Library/"
let swiftFiles = (FileManager.default.enumerator(atPath: swiftRoot)?.compactMap { $0 as? String } ?? [])
    .filter { $0.hasSuffix(".swift") }.sorted()
check(swiftFiles.count > 20, "finds the app's Swift files (run from the repository root)")

func symbolRegex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
let symbolLiteral = symbolRegex(#""([^"\\\n]*)""#)
let symbolLabelled = symbolRegex(#"(?:systemName|systemImage|systemSymbolName|systemImageName):\s*([^,)\n]+)"#)
let symbolHelperCall = symbolRegex(#"\bsymbol\(\s*("[^"\n]*")\s*\)"#)
let symbolIconField = symbolRegex(#"icon:\s*("[^"\n]*")"#)
let symbolReturn = symbolRegex(#"return\s+("[^"\n]*")"#)
let symbolPickerList = symbolRegex(#"symbols = \[([\s\S]*?)\]\.filter"#)
let symbolWelcomeCall = symbolRegex(#"(?:icon|feature|shortcutRow)\([^\n]*"#)
let symbolShaped = symbolRegex(#"^[a-z][a-z0-9.]*$"#)

/// The string literals inside `text`, without their quotes.
func literals(in text: String, matching pattern: NSRegularExpression? = nil) -> [String] {
    let ns = text as NSString
    return symbolLiteral.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        .filter { pattern == nil || pattern!.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
}
/// Every match of `regex` in `text`, as (1-based line, first capture group).
func captures(_ regex: NSRegularExpression, in text: String) -> [(line: Int, text: String)] {
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
        let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        let before = ns.substring(to: match.range.location)
        return (before.filter { $0 == "\n" }.count + 1, ns.substring(with: range))
    }
}

var symbolNames: [(file: String, line: Int, name: String)] = []
var runtimeUsed = Set<String>()
var symbolAllowlistMisses: [String] = []
for path in swiftFiles {
    let text = (try? String(contentsOfFile: swiftRoot + path, encoding: .utf8)) ?? ""
    func record(_ names: [String], _ line: Int) { for name in names { symbolNames.append((path, line, name)) } }
    for (line, raw) in captures(symbolLabelled, in: text) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let names = literals(in: value)
        if names.isEmpty {
            let key = "\(path)|\(value)"
            let listed = runtimeSymbolUses.contains { "\($0.file)|\($0.expression)" == key }
            if listed { runtimeUsed.insert(key) } else { symbolAllowlistMisses.append("\(path):\(line) builds \(value) at runtime") }
        }
        record(names, line)
    }
    for (line, literal) in captures(symbolHelperCall, in: text) { record(literals(in: literal), line) }
    for (line, literal) in captures(symbolIconField, in: text) { record(literals(in: literal, matching: symbolShaped), line) }
    for (line, literal) in captures(symbolReturn, in: text) where path.hasSuffix("Clipboard/ClipItem.swift") {
        record(literals(in: literal, matching: symbolShaped), line)
    }
    for (_, list) in captures(symbolPickerList, in: text) where path.hasSuffix("Manage/IconPicker.swift") {
        record(literals(in: list), 0)
    }
    for (line, call) in captures(symbolWelcomeCall, in: text) where path.hasSuffix("Welcome/WelcomeView.swift") {
        record(literals(in: call, matching: symbolShaped), line)
    }
}
check(symbolNames.count > 40, "the scan finds the symbol names (\(symbolNames.count) found)")
check(symbolAllowlistMisses.isEmpty, "every runtime symbol is in the allowlist: \(symbolAllowlistMisses)")
let unusedRuntime = runtimeSymbolUses.filter { !runtimeUsed.contains("\($0.file)|\($0.expression)") }
check(unusedRuntime.isEmpty, "every runtime allowlist entry still matches the code: \(unusedRuntime.map { "\($0.file) \($0.expression)" })")
for use in symbolNames {
    let resolves = NSImage(systemSymbolName: use.name, accessibilityDescription: nil) != nil
    check(resolves, "SF Symbol \"\(use.name)\" does not resolve (\(use.file):\(use.line))")
}
// ---- update check (pure; no network) ----
let updateNow = Date(timeIntervalSince1970: nowStamp)
check(UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: nil), "a first automatic check is due")
check(!UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: updateNow.addingTimeInterval(-1800)), "half an hour after a check is not due")
check(!UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: updateNow.addingTimeInterval(-3599)), "just under an hour after a check is not due")
check(UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: updateNow.addingTimeInterval(-3600)), "an hour after a check is due")
check(UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: updateNow.addingTimeInterval(-86400)), "a day after a check is due")
check(UpdateRules.automaticCheckIsDue(now: updateNow, lastCheck: updateNow.addingTimeInterval(7200)), "a check in the future (clock set back) is due")
check(UpdateRules.secondsUntilAutomaticCheck(now: updateNow, lastCheck: nil) == 0, "no wait when a check is due at once")
check(UpdateRules.secondsUntilAutomaticCheck(now: updateNow, lastCheck: updateNow.addingTimeInterval(-600)) == 3000, "the wait is the rest of the hour")
check(UpdateRules.secondsUntilAutomaticCheck(now: updateNow, lastCheck: updateNow.addingTimeInterval(-3600)) == 0, "no wait once an hour has passed")
check(UpdateRules.automaticInterval == 3600, "automatic checks run every hour")
check(UpdateRules.displayVersion("v1.10.0") == "1.10.0" && UpdateRules.displayVersion("2.0") == "2.0", "the display version drops a leading v")

let etagJSON = Data(#"{"tag_name":"v1.6.0","name":"Release"}"#.utf8)
check(UpdateRules.fetch(status: 200, etag: "\"abc\"", data: etagJSON, storedTag: nil) == .release(tag: "v1.6.0", etag: "\"abc\""), "a 200 answer gives its tag and ETag")
check(UpdateRules.fetch(status: 200, etag: nil, data: etagJSON, storedTag: "v1.5.0") == .release(tag: "v1.6.0", etag: nil), "a 200 answer replaces the stored tag")
check(UpdateRules.fetch(status: 304, etag: nil, data: Data(), storedTag: "v1.6.0") == .unchanged, "a 304 with a stored tag means unchanged")
check(UpdateRules.fetch(status: 304, etag: nil, data: Data(), storedTag: nil) == .failed, "a 304 with no stored tag is a failure")
check(UpdateRules.fetch(status: 403, etag: nil, data: Data(), storedTag: "v1.6.0") == .failed, "a rate limit or other error is a failure")
check(UpdateRules.fetch(status: 200, etag: "\"abc\"", data: Data("oops".utf8), storedTag: nil) == .failed, "a 200 answer without a tag is a failure")
check(UpdateRules.fetch(status: 200, etag: nil, data: Data(#"{"tag_name":"latest"}"#.utf8), storedTag: nil) == .failed, "a tag that is not a version is a failure")
check(UpdateRules.conditionalETag(storedETag: "\"abc\"", storedTag: "v1.6.0") == "\"abc\"", "the stored ETag is sent with its stored tag")
check(UpdateRules.conditionalETag(storedETag: "\"abc\"", storedTag: nil) == nil, "no ETag is sent without a stored tag")
check(UpdateRules.conditionalETag(storedETag: nil, storedTag: "v1.6.0") == nil && UpdateRules.conditionalETag(storedETag: "", storedTag: "v1.6.0") == nil, "no ETag is sent when none is stored")
check(UpdateRules.availableVersion(latestTag: "v1.6.0", current: "1.5.0") == "v1.6.0", "a newer release is offered")
check(UpdateRules.availableVersion(latestTag: "v1.5.0", current: "1.5.0") == nil, "the same version is not offered")
check(UpdateRules.availableVersion(latestTag: "v1.4.0", current: "1.5.0") == nil, "an older release is not offered")
check(UpdateRules.availableVersion(latestTag: nil, current: "1.5.0") == nil, "no tag offers nothing, so the menu item goes away")
check(UpdateRules.availableVersion(latestTag: "latest", current: "1.5.0") == nil, "a tag that is not a version offers nothing")

// ---- audit: inputs from outside the app ----
check(WebFetch.isWeb(URL(string: "https://a.example.com")!) && WebFetch.isWeb(URL(string: "HTTP://a.example.com")!), "web addresses are http or https")
check(!WebFetch.isWeb(URL(fileURLWithPath: "/etc/hosts")) && !WebFetch.isWeb(URL(string: "file://localhost/etc/hosts")!)
      && !WebFetch.isWeb(URL(string: "httpx://a.example.com")!) && !WebFetch.isWeb(URL(string: "vscode://file/x")!), "other schemes are not web addresses")
check(AppDelegate.webLink(from: " https://example.com/a ")?.host == "example.com", "a web link selection is accepted")
check(AppDelegate.webLink(from: "file:///etc/hosts") == nil && AppDelegate.webLink(from: "httpx://example.com") == nil
      && AppDelegate.webLink(from: "hello") == nil, "non-web selections are refused")
check(AppDelegate.webLink(from: "https://e.com/" + String(repeating: "a", count: 5_000)) == nil, "a selection over 4,096 characters is refused")
var bodyLimit = WebFetch.BodyLimit(limit: 1_000)
check(bodyLimit.add(600) && bodyLimit.add(400) && !bodyLimit.add(1) && bodyLimit.count == 1_001, "a body is refused one byte past its limit")
check(Favicon.maxBytes == 512 * 1024, "favicon limit is 512 KB")
check(blockingRun { await WebFetch.fetch(URL(fileURLWithPath: "/etc/hosts"), limit: 10) == nil }, "a file address is never read")
check(blockingRun { await WebFetch.fetch(URL(string: "ftp://example.com/x")!, limit: 10) == nil }, "an ftp address is never read")
check(Favicon.pixelSizeAllowed(width: 16, height: 16) && Favicon.pixelSizeAllowed(width: 4_096, height: 4_096)
      && !Favicon.pixelSizeAllowed(width: 4_097, height: 16) && !Favicon.pixelSizeAllowed(width: 0, height: 16), "favicon pixel size cap")
if let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
   let smallPNG = small.representation(using: .png, properties: [:]) {
    check(Favicon.pixelsAllowed(smallPNG), "a small favicon is allowed")
}
if let huge = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4_200, pixelsHigh: 4_200, bitsPerSample: 8, samplesPerPixel: 1,
                               hasAlpha: false, isPlanar: false, colorSpaceName: .calibratedWhite, bytesPerRow: 0, bitsPerPixel: 8),
   let hugePNG = huge.representation(using: .png, properties: [:]) {
    check(!Favicon.pixelsAllowed(hugePNG), "a favicon that declares a picture over 4,096 pixels is refused before it decodes")
}
let commandFolder = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-cmd-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: commandFolder, withIntermediateDirectories: true)
let commandText = commandScript("echo hi")
if let written = writeCommandFile(commandText, in: commandFolder) {
    let mode = (try? FileManager.default.attributesOfItem(atPath: written.path))?[.posixPermissions] as? Int
    check(mode == 0o700, "a command file is readable and runnable by you only (mode \(String(describing: mode)))")
    check((try? String(contentsOf: written, encoding: .utf8)) == commandText && commandText.hasPrefix("#!/bin/zsh -il\nrm -f -- \"$0\"\necho hi\n"),
          "the command file removes itself, then runs the command")
} else { check(false, "the command file is written") }
try? FileManager.default.removeItem(at: commandFolder)
let previewChecks = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-preview-\(UUID().uuidString)", isDirectory: true)
if let written = ClipPreviewSource.write(Data("secret".utf8), extension: "txt", in: previewChecks) {
    let mode = (try? FileManager.default.attributesOfItem(atPath: written.path))?[.posixPermissions] as? Int
    check(mode == 0o600, "a preview file is readable by you only")
    ClipPreviewSource.removeLeftovers(in: previewChecks)
    check(!FileManager.default.fileExists(atPath: written.path), "preview files left by an earlier run are removed")
} else { check(false, "the preview file is written") }
let boundedIcons = IconCache(capacity: 10)
for index in 0..<25 { _ = boundedIcons.icon(at: "/copied/\(index)", modified: nil) { NSImage() } }
check(boundedIcons.count <= 10, "the icon cache is bounded")
let boundedDates = ModificationDateCache(capacity: 10)
for index in 0..<25 { _ = boundedDates.modified(at: "/copied/\(index)", now: 0) { nil } }
check(boundedDates.count <= 10, "the modification date cache is bounded")
check(retainedIcons(["live.example.com": NSImage(), "gone.example.com": NSImage()], live: ["live.example.com"]).keys.sorted() == ["live.example.com"],
      "icons of deleted bookmarks are dropped")

blockingRun { await runAuditBenchmark() }
runBenchmark()
QuickOpenBench.main()
ClipboardBench.main()

// ---- Quick Open focus (pure; no windows) ----
check(!QuickOpenFocus.closes(whenKeyGoesTo: .preview, previewOpen: true), "clicking the open preview keeps Quick Open")
check(QuickOpenFocus.closes(whenKeyGoesTo: .preview, previewOpen: false), "a preview that is not open does not keep Quick Open")
check(!QuickOpenFocus.closes(whenKeyGoesTo: .quickOpen, previewOpen: true) && !QuickOpenFocus.closes(whenKeyGoesTo: .quickOpen, previewOpen: false), "Quick Open keeping the key keeps it open")
check(QuickOpenFocus.closes(whenKeyGoesTo: .other, previewOpen: true) && QuickOpenFocus.closes(whenKeyGoesTo: .other, previewOpen: false), "another window closes Quick Open, preview or not")
check(QuickOpenFocus.closes(whenKeyGoesTo: nil, previewOpen: true) && QuickOpenFocus.closes(whenKeyGoesTo: nil, previewOpen: false), "no key window closes Quick Open")

// ---- find duplicates (pure) ----
check(Duplicates.normalizedLink("HTTPS://Docs.Example.com/Path/") == "https://docs.example.com/Path", "scheme and host lowercase, trailing slash goes, path case stays")
check(Duplicates.normalizedLink("docs.example.com/a") == "https://docs.example.com/a", "a missing scheme counts as https")
check(Duplicates.normalizedLink("https://a.com/x?Q=1") != Duplicates.normalizedLink("https://a.com/x?q=1"), "query case matters")
let dupTree = [
    LibraryItem(name: "Docs", url: "https://docs.example.com/"),
    LibraryItem(name: "Work", children: [
        LibraryItem(name: "Docs copy", url: "HTTPS://DOCS.example.com", shortcuts: [Shortcut(keyCode: 2, modifiers: 256, key: "D")], keywords: "wiki handbook"),
        LibraryItem(name: "Other", url: "https://other.example.com"),
    ]),
    LibraryItem(name: "Safari", appPath: "/Applications/Safari.app", keywords: "browser"),
    LibraryItem(name: "Safari again", appPath: "/Applications/Safari.app/", keywords: "Browser web"),
    LibraryItem(name: "Commands", command: "ls"),
    LibraryItem(name: "Divider", isDivider: true),
]
let dupGroups = Duplicates.groups(in: dupTree)
check(dupGroups.count == 2 && dupGroups[0].items.map(\.name) == ["Docs", "Docs copy"] && dupGroups[1].isApp, "groups by link and by app path, in library order")
check(Duplicates.groups(in: [LibraryItem(name: "A", url: "https://a.com"), LibraryItem(name: "B", url: "https://b.com")]).isEmpty, "no duplicates means no groups")
check(Duplicates.folderTitle(of: dupTree[1].children![0].id, in: dupTree) == "Work" && Duplicates.folderTitle(of: dupTree[0].id, in: dupTree) == "Top level", "folder titles")
let merged = Duplicates.merged(dupTree)
check(merged.leaves.map(\.name) == ["Docs", "Other", "Safari", "Commands", "Divider"], "the first item of each group is kept by default")
check(merged.leaves.first { $0.name == "Docs" }?.keywords == "wiki handbook" && merged.leaves.first { $0.name == "Safari" }?.keywords == "browser web", "keywords join unique words, first spelling wins")
check(merged.node(withID: dupTree[1].children![0].id) == nil, "removed item is gone")
let chosen = Duplicates.merged(dupTree, keeping: [dupGroups[0].id: dupTree[1].children![0].id])
check(chosen.leaves.map(\.name) == ["Docs copy", "Other", "Safari", "Commands", "Divider"] && chosen.folders().map(\.title) == ["Work"], "a chosen item is kept, in its own folder")
check(chosen.leaves.first { $0.name == "Docs copy" }?.shortcuts?.isEmpty == false, "the kept item keeps its shortcuts")
check(Duplicates.joinKeywords([nil, "a B", "b c", " "]) == "a B c" && Duplicates.joinKeywords([nil]) == nil, "keyword join")

// ---- bulk edit (pure) ----
let bulkTree = [
    LibraryItem(name: "One", url: "https://one.example.com", color: "red"),
    LibraryItem(name: "Two", appPath: "/Applications/Safari.app", openNew: true),
    LibraryItem(name: "Folder", children: [LibraryItem(name: "Three", url: "https://three.example.com")]),
    LibraryItem(name: "Divider", isDivider: true),
]
let bulkIDs: Set<UUID> = [bulkTree[0].id, bulkTree[1].id, bulkTree[3].id]
let untouched = BulkEdit.apply(BulkEdit(), to: bulkIDs, in: bulkTree)
check(untouched.map(\.icon) == bulkTree.map(\.icon) && untouched.map(\.color) == bulkTree.map(\.color) && untouched[1].openNew == true, "Don't Change keeps everything")
check(BulkEdit().changesNothing && !BulkEdit(icon: .clear).changesNothing, "an empty edit changes nothing")
let edited = BulkEdit.apply(BulkEdit(icon: .set("star.fill"), color: .set("blue"), openNew: .set(false)), to: bulkIDs, in: bulkTree)
check(edited[0].icon == "star.fill" && edited[0].color == "blue" && edited[0].openNew == nil, "set fields change, others do not")
check(edited[1].icon == "star.fill" && edited[1].color == "blue" && edited[1].openNew == nil, "an app takes the color; Opens In resets to existing")
check(edited[2].icon == nil && edited[2].children?[0].icon == nil, "items outside the selection are not touched")
check(edited[3].icon == "star.fill" && edited[3].color == nil, "dividers take an icon but no color")
let cleared = BulkEdit.apply(BulkEdit(icon: .clear, color: .clear, openNew: .set(true)), to: bulkIDs, in: edited)
check(cleared[0].icon == nil && cleared[0].color == nil && cleared[1].openNew == true && cleared[1].icon == nil, "clear removes, Opens In sets new")
check(BulkEdit.apply(BulkEdit(openNew: .set(true)), to: [bulkTree[2].id], in: bulkTree)[2].children?.first?.openNew == nil, "a bookmark in a folder is not changed unless selected")
// ---- library backup: export, restore, and refusals (pure; no panels, no files) ----
/// The refusal a backup gets, or nil when it is read.
func backupError(_ data: Data) -> LibraryBackup.BackupError? {
    if case .failure(let error) = LibraryBackup.decode(data) { return error }
    return nil
}
var backupTree = tree()
backupTree[1].shortcuts = [Shortcut(keyCode: 17, modifiers: 256, key: "T", openNew: true)]
backupTree[1].icon = "star.fill"; backupTree[1].color = "red"; backupTree[1].keywords = "term"
backupTree[2].openAtLogin = true; backupTree[2].promptLabel = "Ticket"
backupTree[2].children?[0].browser = "com.apple.Safari"
let backupFixed = Date(timeIntervalSince1970: 1_800_000_000)
if let exported = try? LibraryBackup.encode(backupTree, exportedAt: backupFixed) {
    if case .success(let restored) = LibraryBackup.decode(exported) {
        check(restored.allIDs == backupTree.allIDs, "backup round trip keeps every id")
        check((try? LibraryBackup.encode(restored, exportedAt: backupFixed)) == exported, "backup round trip re-encodes byte for byte")
        check(restored[1].shortcuts?.first?.description == "⌘T" && restored[1].icon == "star.fill" && restored[1].color == "red"
              && restored[1].keywords == "term" && restored[2].openAtLogin == true && restored[2].children?[0].browser == "com.apple.Safari"
              && restored[2].promptLabel == "Ticket", "backup keeps every field")
    } else { check(false, "backup decodes") }
    let keys = (try? JSONSerialization.jsonObject(with: exported) as? [String: Any])?.keys.sorted()
    check(keys == ["exportedAt", "format", "items", "version"], "backup has only the versioned fields, no clipboard data")
    let text = String(decoding: exported, as: UTF8.self)
    check(!text.contains("clipboard") && !text.contains("pinned"), "backup text has no clipboard data")
    check(text.contains("\"format\" : \"library-backup\"") && text.contains("\"version\" : 1"), "backup is versioned")
    check(backupError(Data(exported.prefix(exported.count - 40))) == .malformed, "truncated backup is rejected")
} else { check(false, "backup encodes") }

if let bare = try? JSONEncoder().encode(backupTree) {
    if case .success(let items) = LibraryBackup.decode(bare) {
        check(items.allIDs == backupTree.allIDs, "bare bookmarks.json array restores")
    } else { check(false, "bare array decodes") }
    check(backupError(Data(bare.prefix(bare.count - 40))) == .malformed, "truncated bookmarks.json array is rejected")
}
check(backupError(Data(#"{"format":"other-app","version":1,"items":[]}"#.utf8)) == .wrongFormat, "wrong format is rejected")
check(backupError(Data(#"{"version":1,"items":[]}"#.utf8)) == .wrongFormat, "missing format is rejected")
check(backupError(Data(#"{"format":"library-backup","version":2,"items":[]}"#.utf8)) == .unsupportedVersion(2), "future version is rejected")
check(backupError(Data(#"{"format":"library-backup","items":[]}"#.utf8)) == .unsupportedVersion(0), "missing version is rejected")
check(backupError(Data("not json".utf8)) == .malformed && backupError(Data()) == .malformed, "garbage is rejected")
check(backupError(Data(#"{"format":"library-backup","version":1,"items":"oops"}"#.utf8)) == .malformed, "bad items are rejected")
let twin = LibraryItem(name: "Twin", url: "https://twin.example.com")
var clash = LibraryItem(name: "Other", url: "https://other.example.com")
clash.id = twin.id
if let dupes = try? LibraryBackup.encode([twin, clash]) {
    check(backupError(dupes) == .duplicateIDs, "repeated ids are rejected")
}
check(LibraryBackup.BackupError.unsupportedVersion(2).message.contains("version 2"), "version error names the version")

print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
