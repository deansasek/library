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
check(templateFieldList(in: "x.example.com/{}") == [TemplateField(name: "", label: nil)], "bare placeholder is one unnamed field")
check(templateFieldList(in: "a/{}/{}") == [TemplateField(name: "", label: nil)], "repeated bare placeholder is one field")
check(templateFieldList(in: "a/{ticket:Ticket number}/{user}/{ticket}", declared: ["ticket", "user"]) == [
    TemplateField(name: "ticket", label: "Ticket number"), TemplateField(name: "user", label: nil),
], "declared fields share a name and keep the first label")
check(templateFieldList(in: "a/{ticket}/{ticket:Later}", declared: ["ticket"]).first?.label == "Later", "a label given later fills in a bare name")
check(templateFieldList(in: "a/{:Only label}").first == TemplateField(name: "", label: "Only label"), "a label without a name")
check(templateFieldList(in: "a/{ticket:}", declared: ["ticket"]).first == TemplateField(name: "ticket", label: nil), "empty label is no label")
check(templateFieldList(in: "a/{open", declared: ["open"]).isEmpty && templateFieldList(in: "a/{x{}").map(\.name) == [""], "unclosed braces are text")
check(!LibraryItem(name: "Plain", url: "a.example.com/{open").isTemplate && !LibraryItem(name: "N", url: "a/{id}").isTemplate, "undeclared named braces are plain text")
let oldJSON = Data(#"{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","name":"Jira","url":"x.example.com/{}"}"#.utf8)
let oldItem = try? JSONDecoder().decode(LibraryItem.self, from: oldJSON)
check(oldItem?.templateFields == nil && oldItem?.isTemplate == true, "a file without templateFields loads, and {} still asks")
if let declared = oldItem.map({ var item = $0; item.templateFields = ["q:Query"]; return item }),
   let data = try? JSONEncoder().encode(declared), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.templateFields == ["q:Query"], "declared fields round-trip through the file")
} else {
    check(false, "declared fields round-trip through the file")
}
check(LibraryItem(name: "N", url: "a/{id}").placeholders.isEmpty && templatePreview("a/{id}") == "a/{id}" && withoutPlaceholders("a/{id}") == "a/{id}", "undeclared braces are not a template, preview or removal")
check(LibraryItem(name: "N", url: "a/{id}", templateFields: ["id"]).isTemplate, "declared named field is a template")
check(templateFieldList(in: "a/{id}/{x}", declared: ["id"]).map(\.name) == ["id"] && templateFieldList(in: "a/{id}/{x}", declared: ["id"]).count == 1, "undeclared names in a template stay text")
check(parseTemplateFields("query:Search terms, sort , ,:NoName, query:Again, ,") == ["query:Search terms", "sort"], "Fields text: names, labels, blanks and repeats")
check(parseTemplateFields("  ") == nil && parseTemplateFields("a{b, c}d, e") == ["e"] && parseTemplateFields("x:") == ["x"], "Fields text: empty and braces dropped")
let declaredBug = LibraryItem(name: "Declared", url: "a.example.com/{q}?x={q:Other}", templateFields: parseTemplateFields("q:Search"))
check(declaredBug.placeholders == [TemplateField(name: "q", label: "Search")], "declared label beats the URL label")
check(declaredBug.link(values: ["q": "a b&c"])?.absoluteString == "https://a.example.com/a%20b%26c?x=a%20b%26c", "declared fields fill and encode as before")
check(declaredBug.link(values: [:]) == nil, "declared values are required")
check(fillTemplate("a/{q}", values: ["q": "x"]) == "a/{q}" && fillTemplate("a/{q}/{}", values: ["": "x"]) == "a/{q}/x", "undeclared braces are untouched by a fill")
let bug = LibraryItem(name: "Bug", url: "bugs.example.com/{project}/{id:Issue}?q={project}", templateFields: ["project", "id"])
check(bug.placeholders.map(\.name) == ["project", "id"], "two fields, project shared")
check(bug.link(values: ["project": "WEB", "id": "12 3"])?.absoluteString == "https://bugs.example.com/WEB/12%203?q=WEB", "several values fill every placeholder")
check(bug.link(values: ["project": "WEB"]) == nil && bug.link(values: [:]) == nil, "a missing value is rejected")
check(bug.link(values: ["project": "a b/c", "id": "1"])?.absoluteString == "https://bugs.example.com/a%20b%2Fc/1?q=a%20b%2Fc", "named values encode the same way")
check(jira.link(values: ["": "ABC-123"])?.absoluteString == "https://x.example.com/browse/ABC-123", "bare value by its empty name")
check(bug.link(values: ["project": "", "id": ""])?.absoluteString == "https://bugs.example.com//?q=", "empty values still fill, the caller rejects them")
check(templatePreview("a/{id:Issue}/{}/{id}/{user}", declared: ["id", "user"]) == "a/‹Issue›/‹value›/‹Issue›/‹user›", "preview labels")
check(templatePreview("a/{id:Issue}/{}/{id}/{user}") == "a/{id:Issue}/‹value›/{id}/{user}", "preview leaves undeclared braces")
check(withoutPlaceholders("a/{}/{x:Y}/b", declared: ["x"]) == "a///b" && withoutPlaceholders("a/{}/{x:Y}/b") == "a//{x:Y}/b", "placeholders removed, undeclared kept")
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

// ---- folder Show Open All ----
check(LibraryItem(name: "F", children: []).showsOpenAllItem, "a folder with no setting shows Open All")
check(LibraryItem(name: "F", children: [], showsOpenAll: true).showsOpenAllItem, "a folder set to show shows Open All")
check(!LibraryItem(name: "F", children: [], showsOpenAll: false).showsOpenAllItem, "a folder set to hide hides Open All")
let oaOldFolder = Data(#"{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABD","name":"Work","children":[]}"#.utf8)
let oaDecoded = try? JSONDecoder().decode(LibraryItem.self, from: oaOldFolder)
check(oaDecoded?.showsOpenAll == nil && oaDecoded?.showsOpenAllItem == true, "a folder file without showsOpenAll loads and shows Open All")
var oaHidden = LibraryItem(name: "Hidden", children: [], showsOpenAll: false)
if let data = try? JSONEncoder().encode(oaHidden), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.showsOpenAll == false && !back.showsOpenAllItem, "a hidden Open All round-trips through the file")
} else {
    check(false, "a hidden Open All round-trips through the file")
}
oaHidden.showsOpenAll = nil
if let data = try? JSONEncoder().encode(oaHidden), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.showsOpenAll == nil && back.showsOpenAllItem, "a shown Open All round-trips as no field")
} else {
    check(false, "a shown Open All round-trips as no field")
}

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
// Space previews only with an empty search, so a typed space reaches the field in a multi-word search.
check(QuickOpenModel.spaceTogglesPreview(query: "", showActions: false, selectionIsClip: true), "Space previews a selected clip with an empty search")
check(!QuickOpenModel.spaceTogglesPreview(query: "hello", showActions: false, selectionIsClip: true), "Space types while the search has text")
check(!QuickOpenModel.spaceTogglesPreview(query: "", showActions: false, selectionIsClip: false), "Space types when the selection is not a clip")
check(!QuickOpenModel.spaceTogglesPreview(query: "", showActions: true, selectionIsClip: true), "Space types while actions are showing")

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
let openedSnippet = savedSnippets.snippets[0]
var renamedSnippet = openedSnippet
renamedSnippet.name = "Signature"
savedSnippets.update(renamedSnippet, changedFrom: openedSnippet)
check(SnippetStore(file: snippetFile).snippets.first?.name == "Signature", "an edit is saved")
// An editor saves only the fields it changed, so an edit made in another window is kept.
let mergeBase = Snippet(name: "Address", text: "1 Main St", keywords: "home")
let mergeStore = SnippetStore(file: nil)
mergeStore.add(mergeBase)
var otherWindowEdit = mergeBase
otherWindowEdit.name = "Home address"
mergeStore.update(otherWindowEdit, changedFrom: mergeBase)
var editorEdit = mergeBase
editorEdit.text = "2 Main St"
check(mergeStore.update(editorEdit, changedFrom: mergeBase), "an edit of a snippet that still exists is saved")
check(mergeStore.snippets.first?.name == "Home address" && mergeStore.snippets.first?.text == "2 Main St"
      && mergeStore.snippets.first?.keywords == "home", "a save keeps the fields another window changed")
mergeStore.remove([mergeBase.id])
check(!mergeStore.update(editorEdit, changedFrom: mergeBase) && mergeStore.snippets.isEmpty,
      "an edit of a removed snippet is refused, so its text stays in the editor")
savedSnippets.remove([renamedSnippet.id])
check(SnippetStore(file: snippetFile).snippets.isEmpty, "a delete is saved")
let damagedSnippetFile = snippetDir.appendingPathComponent("damaged-snippets.json")
try? Data("not a list".utf8).write(to: damagedSnippetFile)
let movedSnippets = SnippetStore(file: damagedSnippetFile)
check(movedSnippets.snippets.isEmpty && !FileManager.default.fileExists(atPath: damagedSnippetFile.path)
      && FileManager.default.fileExists(atPath: snippetDir.appendingPathComponent("snippets-damaged.json").path),
      "a damaged snippets file is moved aside, not read as snippets")
// snippets.json records its format version. A bare list from before the version was added still loads.
let versionedData = (try? Data(contentsOf: snippetFile)) ?? Data()
let versionedObject = (try? JSONSerialization.jsonObject(with: versionedData)) as? [String: Any]
check(versionedObject?["version"] as? Int == 1 && versionedObject?["snippets"] is [Any],
      "snippets.json is saved with a format version")
let legacySnippetFile = snippetDir.appendingPathComponent("legacy-snippets.json")
try? JSONEncoder().encode([Snippet(name: "Old", text: "Kept")]).write(to: legacySnippetFile)
check(SnippetStore(file: legacySnippetFile).snippets.map(\.name) == ["Old"], "a snippets file without a version still loads")
// A file from a newer release is left as it is, and saving is blocked so it is not overwritten.
let newerSnippetFile = snippetDir.appendingPathComponent("newer-snippets.json")
let newerText = Data(#"{"version": 2, "snippets": [], "groups": []}"#.utf8)
try? newerText.write(to: newerSnippetFile)
let newerSnippets = SnippetStore(file: newerSnippetFile)
newerSnippets.add(Snippet(name: "Blocked", text: "Not saved"))
check(newerSnippets.saveBlocked && newerSnippets.snippets.isEmpty && (try? Data(contentsOf: newerSnippetFile)) == newerText,
      "a snippets file from a newer release is not changed")
// A snippets.json that exists but cannot be read (a directory here) blocks saving: changes do nothing and nothing is written.
let blockedSnippetFile = snippetDir.appendingPathComponent("blocked-snippets.json")
try? FileManager.default.createDirectory(at: blockedSnippetFile, withIntermediateDirectories: true)
let blockedSnippets = SnippetStore(file: blockedSnippetFile)
blockedSnippets.add(Snippet(name: "Lost", text: "Not saved"))
check(blockedSnippets.saveBlocked && blockedSnippets.snippets.isEmpty, "an unreadable snippets file blocks changes")
var blockedIsDirectory: ObjCBool = false
check(FileManager.default.fileExists(atPath: blockedSnippetFile.path, isDirectory: &blockedIsDirectory) && blockedIsDirectory.boolValue,
      "a change while blocked does not replace the unreadable file")
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
    // The paste queue: in order, Paste Next copies the first clip and takes it out, and Clear Queue empties it.
    let queued = Array(history.displayOrder.prefix(2))
    check(history.pasteQueue.isEmpty && queued.count == 2, "the queue starts empty")
    history.enqueue(queued[0])
    history.enqueue(queued[1])
    check(history.pasteQueue.map(\.id) == queued.map(\.id), "queued clips keep their order")
    let (queueMenu, queueTarget) = PopupMenu.makeClipboardMenu(history: history, suggestion: nil, pastes: false)
    check(queueMenu.items.contains { $0.isSectionHeader && $0.title == "Paste Queue (2)" }, "queue header counts the clips")
    check(queueMenu.items.filter { !$0.isEnabled && !$0.isSeparatorItem && !$0.isSectionHeader }.map(\.title) == queued.map(\.menuTitle), "queued clips are listed, not chosen")
    check(queueMenu.items.contains { $0.title == "Paste Next" && $0.isEnabled } && queueMenu.items.contains { $0.title == "Clear Queue" }, "queue has Paste Next and Clear Queue")
    history.pasteNext()
    check(board.string(forType: .string) == queued[0].plainText && history.pasteQueue.map(\.id) == [queued[1].id], "Paste Next copies the first clip and removes it")
    history.pasteNext()
    history.pasteNext()
    check(history.pasteQueue.isEmpty && board.string(forType: .string) == queued[1].plainText, "Paste Next on an empty queue does nothing")
    history.enqueue(queued[0])
    history.clearPasteQueue()
    check(history.pasteQueue.isEmpty, "Clear Queue empties the queue")
    check(PopupMenu.makeClipboardMenu(history: history, suggestion: nil, pastes: false).menu.items.allSatisfy { !($0.title.hasPrefix("Paste Queue")) }, "no queue section when the queue is empty")
    _ = queueTarget
    // A cleared or removed clip is forgotten: it is no longer the current clip (so it is not suggested) or in the queue.
    copy("https://forgotten.example.com/clear")
    check(history.current?.kind == .link, "the copied link is the current clip")
    history.clear()
    check(history.current == nil, "clear forgets the current clip")
    check(AddSuggestion.make(selection: nil, clipboard: history.current, in: tree()) == nil, "a cleared link is not suggested")
    copy("queued then removed")
    if let doomed = history.current {
        history.enqueue(doomed)
        history.remove(doomed)
        check(history.current == nil && history.pasteQueue.isEmpty, "removing a clip forgets it and drops it from the queue")
    } else { check(false, "the copy is the current clip") }
    let node = LibraryItem(name: "docs.example.com", url: "https://docs.example.com")
    let (withAdd, addTarget) = PopupMenu.makeClipboardMenu(history: history, suggestion: AddSuggestion(node: node, source: .selection), pastes: false)
    check(withAdd.items.first?.title == "Add “docs.example.com” to Library", "suggestion first")
    _ = (target, pasteTarget, addTarget)
}

// ---- clipboard transforms (Copy as…) ----
let transformTable: [(ClipTransform, String, String)] = [
    (.plainText, "  Hi\nthere ", "  Hi\nthere "),
    (.trimmed, "  Hi there \n\t", "Hi there"),
    (.trimmed, "\n \n", ""),
    (.trimmed, "inner  spaces\nkept", "inner  spaces\nkept"),
    (.lowercase, "Hello WORLD é", "hello world é"),
    (.lowercase, "already", "already"),
    (.uppercase, "Straße café", "STRASSE CAFÉ"),
    (.uppercase, "", ""),
    (.joinedLines, "one\ntwo\r\nthree\rfour", "one two three four"),
    (.joinedLines, "a\n\nb", "a  b"),
    (.joinedLines, "single", "single"),
    (.joinedLines, "trailing\n", "trailing "),
    (.smartPunctuation, "\"Hi\" there", "“Hi” there"),
    (.smartPunctuation, "He said \"don't\"", "He said “don’t”"),
    (.smartPunctuation, "don't stop", "don’t stop"),
    (.smartPunctuation, "The dogs' bowls", "The dogs’ bowls"),
    (.smartPunctuation, "'quoted' word", "‘quoted’ word"),
    (.smartPunctuation, "'90s music", "’90s music"),
    (.smartPunctuation, "wait -- what", "wait — what"),
    (.smartPunctuation, "one... two", "one… two"),
    (.smartPunctuation, "wait....", "wait…."),
    (.smartPunctuation, "5\" screen", "5” screen"),
    (.smartPunctuation, "(\"parens\")\n\"next line\"", "(“parens”)\n“next line”"),
    (.smartPunctuation, "plain text, nothing: 1 < 2 & 3 > 2.", "plain text, nothing: 1 < 2 & 3 > 2."),
    (.smartPunctuation, "already “curly” and ‘too’ — …", "already “curly” and ‘too’ — …"),
    (.smartPunctuation, "", ""),
]
for (transform, input, expected) in transformTable {
    check(transform.apply(input) == expected, "\(transform) of \(input.debugDescription) gives \(expected.debugDescription)")
}
check(ClipTransform.allCases.map(\.title).allSatisfy { !$0.isEmpty } && ClipTransform.allCases.count == 6, "six named transforms")

// ---- smart text: address, phone, and date in a text clip (on-device detection) ----
let smartTable: [(text: String, address: Bool, phone: String?, date: Bool)] = [
    ("Ship to 1 Infinite Loop, Cupertino, CA 95014", true, nil, false),
    ("Call +1 (415) 555-0132 after lunch", false, "+14155550132", false),
    ("Call 415.555.0199 anytime", false, "4155550199", false),
    ("Meeting on December 25, 2026 at 2:30 PM", false, nil, true),
    ("Just some plain words here", false, nil, false),
    ("Lunch at 1 Infinite Loop on December 25, 2026 at noon, call 415.555.0199", true, "4155550199", true),
]
for row in smartTable {
    let found = SmartText.detect(row.text)
    check((found.address != nil) == row.address, "address in \(row.text.debugDescription): \(found.address ?? "none")")
    check(found.phone.map(SmartText.phoneDigits) == row.phone, "phone in \(row.text.debugDescription): \(found.phone ?? "none")")
    check((found.date != nil) == row.date, "date in \(row.text.debugDescription)")
}
check(SmartText.detect("Ship to 1 Infinite Loop, Cupertino, CA 95014").address?.contains("Infinite Loop") == true, "the address is the matched text")
check(SmartText.detect("Call 415.555.0199 or 415.555.0100").phone.map(SmartText.phoneDigits) == "4155550199", "the first phone number wins")
check(SmartText.detect("").address == nil && SmartText.detect("").phone == nil && SmartText.detect("").date == nil, "empty text has no matches")
check(SmartText.phoneDigits("+1 (415) 555-0132") == "+14155550132" && SmartText.phoneDigits("415.555.0199 ext.") == "4155550199", "phone digits keep only digits and plus")
check(SmartText.mapsURL(for: "1 Infinite Loop, Cupertino")?.host == "maps.apple.com"
      && URLComponents(url: SmartText.mapsURL(for: "1 Infinite Loop, Cupertino")!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "1 Infinite Loop, Cupertino", "Maps opens the address as the query")
let icsStart = SmartText.DetectedDate(start: Date(timeIntervalSince1970: 0), duration: 0)
let ics = SmartText.calendarEvent(text: "  Lunch; rooms, 2\nsecond line", date: icsStart, created: Date(timeIntervalSince1970: 0), uid: "T1")
check(ics.hasPrefix("BEGIN:VCALENDAR\r\n") && ics.hasSuffix("END:VCALENDAR\r\n"), "the event is a calendar file with CRLF lines")
check(ics.contains("DTSTART:19700101T000000Z\r\n") && ics.contains("DTEND:19700101T010000Z\r\n"), "no length gives a one-hour event")
check(ics.contains("SUMMARY:Lunch\\; rooms\\, 2\r\n") && !ics.contains("second line"), "summary is the first line, with commas and semicolons escaped")
check(ics.contains("UID:T1@library\r\n"), "the event has its UID")

// ---- Markdown links ----
check(MarkdownLink.escapedTitle("a [b] *c* _d_ `e` \\f") == "a \\[b\\] \\*c\\* \\_d\\_ \\`e\\` \\\\f", "Markdown special characters are escaped")
check(MarkdownLink.escapedTitle("Plain (words) & #tags") == "Plain (words) & #tags", "other characters are left alone")
check(MarkdownLink.markdown(title: "Docs", url: "https://docs.example.com/a") == "[Docs](https://docs.example.com/a)", "plain Markdown link")
check(MarkdownLink.markdown(title: "Hi (there)", url: "https://x.example.com/a b(c)") == "[Hi (there)](https://x.example.com/a%20b%28c%29)", "destination encodes spaces and parentheses")
check(MarkdownLink.markdown(title: "  Docs  ", url: "https://d.example.com") == "[Docs](https://d.example.com)", "title is trimmed")
check(MarkdownLink.markdown(title: " ", url: "https://d.example.com") == "[https://d.example.com](https://d.example.com)", "a blank title uses the URL")
check(MarkdownLink.markdown(title: "a_b [c]", url: "https://e.example.com") == "[a\\_b \\[c\\]](https://e.example.com)", "escaped title in the link")
let mdRich = MarkdownLink.richText(title: "Docs & *more*", url: "https://docs.example.com")
let mdBack = mdRich.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
check(mdBack?.string == "Docs & *more*" && (mdBack?.attribute(.link, at: 0, effectiveRange: nil) as? URL) == URL(string: "https://docs.example.com"), "rich text holds the unescaped title as a link")
check(MarkdownLink.richText(title: "  ", url: "https://docs.example.com") == nil && MarkdownLink.richText(title: "Docs", url: "") == nil, "no rich text without a title or valid URL")
let mdPasteboard = NSPasteboard(name: NSPasteboard.Name("library-checks-markdown-\(UUID().uuidString)"))
MarkdownLink.copy(title: "Docs", url: "https://docs.example.com", to: mdPasteboard)
check(mdPasteboard.string(forType: .string) == "[Docs](https://docs.example.com)" && mdPasteboard.data(forType: .rtf) != nil, "copy writes plain text and rich text")
MarkdownLink.copy(title: "", url: "https://docs.example.com", to: mdPasteboard)
check(mdPasteboard.string(forType: .string) == "[https://docs.example.com](https://docs.example.com)" && mdPasteboard.data(forType: .rtf) == nil, "copy without a title writes plain text only")
mdPasteboard.releaseGlobally()

// ---- from <app> filter ----
let fromApps = ["Safari", "Google", "Google Chrome", "Notes", "Safari Technology Preview"]
check(SourceFilter.parse("from safari", apps: fromApps) == SourceFilter.Match(app: "Safari", rest: ""), "from an app alone")
check(SourceFilter.parse("FROM safari hello world", apps: fromApps) == SourceFilter.Match(app: "Safari", rest: "hello world"), "case-insensitive, words after the app")
check(SourceFilter.parse("from google chrome docs", apps: fromApps) == SourceFilter.Match(app: "Google Chrome", rest: "docs"), "the longest app name wins")
check(SourceFilter.parse("from google docs", apps: fromApps) == SourceFilter.Match(app: "Google", rest: "docs"), "a shorter app name when the longer one does not match")
check(SourceFilter.parse("from  notes   meeting ", apps: fromApps) == SourceFilter.Match(app: "Notes", rest: "meeting"), "extra spaces are ignored")
check(SourceFilter.parse("from safari technology", apps: fromApps) == SourceFilter.Match(app: "Safari", rest: "technology"), "a name is not taken from a longer name not typed")
check(SourceFilter.parse("from safari technology preview", apps: fromApps) == SourceFilter.Match(app: "Safari Technology Preview", rest: ""), "the full name matches")
check(SourceFilter.parse("from", apps: fromApps) == nil && SourceFilter.parse("from zzz", apps: fromApps) == nil, "from alone is a word")
check(SourceFilter.parse("from safari", apps: []) == nil && SourceFilter.parse("from notes", apps: ["Google"]) == nil, "no app in the history, no filter")
check(SourceFilter.parse("from google chrome", apps: ["Google"]) == SourceFilter.Match(app: "Google", rest: "chrome"), "a shorter name leaves the rest as text")
check(SourceFilter.parse("hello from safari", apps: fromApps) == nil && SourceFilter.parse("fromage cheese", apps: fromApps) == nil, "from must start the query")
check(SourceFilter.parse("from safari", apps: ["", "  "]) == nil, "blank app names never match")
check(SourceFilter.includes("Safari", app: "safari") && !SourceFilter.includes("Notes", app: "Safari") && !SourceFilter.includes(nil, app: "Safari"), "clips match their source app, case-insensitively")
// A locked clip's source app is not listed in the "from" completions.
let openedClip = clip(.text, text: "open")
let lockedClip = clip(.text, text: "locked")
var appClips = [openedClip, lockedClip]
appClips[0].sourceApp = "Notes"
appClips[1].sourceApp = "Password Manager"
check(ClipboardHistory.sourceApps(in: appClips) { $0.id == lockedClip.id } == ["Notes"], "a locked clip's source app is not listed")
check(ClipboardHistory.sourceApps(in: appClips) { _ in false } == ["Notes", "Password Manager"], "every unlocked source app is listed, in name order")

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
    ("QuickOpen/QuickOpenView.swift", "icon", "the icon of a Quick Open action; its literals are read by the icon: rule in QuickOpenModel.swift"),
    ("Manage/NodeRow.swift", "warning.symbol", "the symbol of linkWarning, which returns only the two literal names exclamationmark.triangle and wifi.exclamationmark"),
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
let merged = Duplicates.merge(dupTree).nodes
check(merged.leaves.map(\.name) == ["Docs", "Other", "Safari", "Commands", "Divider"], "the first item of each group is kept by default")
check(merged.leaves.first { $0.name == "Docs" }?.keywords == "wiki handbook" && merged.leaves.first { $0.name == "Safari" }?.keywords == "browser web", "keywords join unique words, first spelling wins")
check(merged.node(withID: dupTree[1].children![0].id) == nil, "removed item is gone")
let chosen = Duplicates.merge(dupTree, keeping: [dupGroups[0].id: dupTree[1].children![0].id]).nodes
check(chosen.leaves.map(\.name) == ["Docs copy", "Other", "Safari", "Commands", "Divider"] && chosen.folders().map(\.title) == ["Work"], "a chosen item is kept, in its own folder")
check(chosen.leaves.first { $0.name == "Docs copy" }?.shortcuts?.isEmpty == false, "the kept item keeps its shortcuts")
check(Duplicates.joinKeywords([nil, "a B", "b c", " "]) == "a B c" && Duplicates.joinKeywords([nil]) == nil, "keyword join")

// ---- merging keeps the shortcuts of the copies (pure) ----
let mergeCmdD = Shortcut(keyCode: 2, modifiers: UInt32(cmdKey), key: "D")
let mergeCmdE = Shortcut(keyCode: 14, modifiers: UInt32(cmdKey), key: "E")
let inheritTree = [
    LibraryItem(name: "Docs", url: "https://docs.example.com"),
    LibraryItem(name: "Docs copy", url: "https://docs.example.com", shortcuts: [mergeCmdD]),
    LibraryItem(name: "Docs old", url: "https://docs.example.com/"),
]
let inherit = Duplicates.merge(inheritTree)
check(inherit.nodes.map(\.name) == ["Docs"] && inherit.nodes[0].shortcuts == [mergeCmdD], "the kept item inherits a shortcut from a copy")
check(inherit.summary == "Merged 3 items. 1 shortcut was kept from another copy." && inherit.conflicts.isEmpty, "summary after inheriting one shortcut")
let chosenCopy = Duplicates.merge(inheritTree, keeping: [Duplicates.groups(in: inheritTree)[0].id: inheritTree[1].id])
check(chosenCopy.nodes.map(\.name) == ["Docs copy"] && chosenCopy.inheritedCount == 0 && chosenCopy.summary == "Merged 3 items.", "a chosen copy keeps its own shortcut and inherits nothing it already has")
let clashTree = [
    LibraryItem(name: "Docs", url: "https://docs.example.com", shortcuts: [mergeCmdD]),
    LibraryItem(name: "Docs copy", url: "https://docs.example.com", shortcuts: [Shortcut(keyCode: 2, modifiers: UInt32(cmdKey), key: "d"), mergeCmdE]),
]
let clash = Duplicates.merge(clashTree)
check(clash.nodes[0].shortcuts == [mergeCmdD, mergeCmdE], "a clashing copy shortcut is dropped, the other is inherited")
check(clash.conflicts == ["⌘d (Docs copy)"] && clash.summary == "Merged 2 items. 1 shortcut was kept from another copy. Not kept, because the key is already used: ⌘d (Docs copy).", "a clash is listed in the summary")
let elsewhere = [
    LibraryItem(name: "Mail", url: "https://mail.example.com", shortcuts: [mergeCmdE]),
    LibraryItem(name: "Docs", url: "https://docs.example.com"),
    LibraryItem(name: "Docs copy", url: "https://docs.example.com", shortcuts: [mergeCmdE]),
]
let elsewhereResult = Duplicates.merge(elsewhere)
check(elsewhereResult.nodes.first { $0.name == "Docs" }?.shortcuts == nil && elsewhereResult.summary == "Merged 2 items. Not kept, because the key is already used: ⌘E (Docs copy).", "a key used by another item is a clash")
let twoCopies = [
    LibraryItem(name: "Docs", url: "https://docs.example.com"),
    LibraryItem(name: "Docs b", url: "https://docs.example.com", shortcuts: [mergeCmdD]),
    LibraryItem(name: "Docs c", url: "https://docs.example.com", shortcuts: [mergeCmdD]),
]
let twoCopiesResult = Duplicates.merge(twoCopies)
check(twoCopiesResult.nodes[0].shortcuts == [mergeCmdD] && twoCopiesResult.inheritedCount == 1 && twoCopiesResult.conflicts == ["⌘D (Docs c)"], "two copies with one key: the first wins, the second is listed")
let plainCopies = [LibraryItem(name: "A", url: "https://a.example.com"), LibraryItem(name: "B", url: "https://a.example.com")]
check(Duplicates.merge(plainCopies).summary == "Merged 2 items." && Duplicates.merge(plainCopies).nodes[0].shortcuts == nil, "no shortcuts to keep means a plain summary")
// A removed copy keeps its notes, color and folder, so it can go to Recently Deleted with them.
do {
    var noted = LibraryItem(name: "Docs copy", url: "https://docs.example.com")
    noted.note = "keep me"
    noted.color = "red"
    let inFolder = [LibraryItem(name: "Work", children: [LibraryItem(name: "Docs", url: "https://docs.example.com"), noted])]
    let notedMerge = Duplicates.merge(inFolder)
    check(notedMerge.removed.map(\.name) == ["Docs copy"] && notedMerge.removed[0].note == "keep me" && notedMerge.removed[0].color == "red",
          "a removed copy keeps its notes and color")
    check(notedMerge.removed[0].deletedFrom == inFolder[0].id, "a removed copy remembers its folder")
    check(Duplicates.merge(plainCopies).removed.count == 1, "one removed copy is listed")
}
// An app with other arguments, or a link in another browser, opens something else, so it is not a duplicate.
let sameApp = [LibraryItem(name: "T1", appPath: "/Applications/Terminal.app", arguments: "-x"), LibraryItem(name: "T2", appPath: "/Applications/Terminal.app", arguments: "-x ")]
check(Duplicates.groups(in: sameApp).count == 1, "apps with the same arguments are duplicates")
check(Duplicates.groups(in: [LibraryItem(name: "T3", appPath: "/Applications/Terminal.app", arguments: "--new"), LibraryItem(name: "T4", appPath: "/Applications/Terminal.app")]).isEmpty, "apps with other arguments are not duplicates")
check(Duplicates.groups(in: [LibraryItem(name: "Docs", url: "https://docs.example.com", browser: "com.apple.Safari"), LibraryItem(name: "Docs copy", url: "https://docs.example.com")]).isEmpty, "links in other browsers are not duplicates")

// A bookmark keeps a URL with its own scheme, such as mailto: or obsidian://. A host and port still get https://.
check(LibraryItem(name: "Vault", url: "obsidian://open?vault=Notes").link?.absoluteString == "obsidian://open?vault=Notes", "a custom URL scheme opens as written")
check(LibraryItem(name: "Mail", url: "mailto:me@example.com").link?.absoluteString == "mailto:me@example.com", "a mailto link keeps its scheme")
check(LibraryItem(name: "Local", url: "localhost:8080/app").link?.absoluteString == "https://localhost:8080/app", "a host with a port gets https")
check(LibraryItem(name: "Plain", url: "example.com/a?u=http://x").link?.absoluteString == "https://example.com/a?u=http://x", "a host whose query has a link gets https")
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
// ---- newer values in a file do not stop the library from loading ----
do {
    let newer = #"[{"id":"00000000-0000-0000-0000-000000000001","name":"Later","url":"https://example.com","readLater":"archived"}]"#
    if case .success(let items) = LibraryBackup.decode(Data(newer.utf8)) {
        check(items.first?.readLater == .unknown, "an unknown reading-list value loads as unknown")
    } else {
        check(false, "a file with an unknown reading-list value still loads")
    }
}

// ---- update command: the release's checksum is checked before install.sh runs ----
do {
    let command = UpdateCheck.installCommand(tag: "v1.6.5")
    check(command.contains("shasum -a 256 -c"), "update checks the checksum")
    check(command.contains("releases/download/v1.6.5/Library-1.6.5.zip.sha256"), "update downloads the release checksum")
    let verifyAt = command.range(of: "shasum -a 256 -c")!.lowerBound
    let installAt = command.range(of: "install.sh")!.lowerBound
    check(verifyAt < installAt, "the checksum is checked before install.sh runs")
    check(!command.contains("git clone"), "update no longer clones the repository")
}

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
        var loginCommand = LibraryItem(name: "Login", command: "echo hi")
        loginCommand.openAtLogin = true
        if case .success(let fromFile) = LibraryBackup.decode(try! JSONEncoder().encode([loginCommand])) {
            check(fromFile.first?.openAtLogin == nil, "a restored command does not run at login by itself")
        }
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
var backupClash = LibraryItem(name: "Other", url: "https://other.example.com")
backupClash.id = twin.id
if let dupes = try? LibraryBackup.encode([twin, backupClash]) {
    check(backupError(dupes) == .duplicateIDs, "repeated ids are rejected")
}
check(LibraryBackup.BackupError.unsupportedVersion(2).message.contains("version 2"), "version error names the version")
// A restore leaves Recently Deleted out of the library, and an id that Recently Deleted uses is given a new one.
let trashedOld = LibraryItem(name: "Trashed", url: "https://trashed.example.com", deletedDate: backupFixed)
var folderFromBackup = LibraryItem(name: "Folder", children: [])
var innerFromBackup = LibraryItem(name: "Inner", url: "https://inner.example.com")
innerFromBackup.id = trashedOld.id
folderFromBackup.children = [innerFromBackup]
let fileItems = [folderFromBackup, LibraryItem(name: "Ghost", url: "https://ghost.example.com", deletedDate: backupFixed),
                 LibraryItem(name: "Plain", url: "https://plain.example.com")]
let restorable = LibraryBackup.restorable(fileItems, avoiding: [trashedOld])
check(restorable.map(\.name) == ["Folder", "Plain"], "a restore leaves Recently Deleted items out of the library")
check(restorable[0].children?[0].name == "Inner" && restorable[0].children?[0].id != trashedOld.id, "a restored child never reuses a Recently Deleted id")
check(Set(restorable.allIDs).count == restorable.allIDs.count, "restored ids stay unique")
check(LibraryBackup.restorable(fileItems, avoiding: []).first?.children?[0].id == innerFromBackup.id, "ids are kept when nothing collides")
// ---- iCloud Drive library (rules and file steps; temporary folders, never the real iCloud Drive) ----
func syncItem(_ name: String, id: UUID = UUID(), children: [LibraryItem]? = nil) -> LibraryItem {
    LibraryItem(id: id, name: name, url: "https://\(name).example.com", children: children)
}
func daysAgo(_ days: Double, from now: Date) -> Date { now.addingTimeInterval(-days * 24 * 60 * 60) }

// Prompt and steps
check(LibrarySync.enablePrompt(iCloudFolderExists: false, cloudFileExists: true) == .unavailable, "no iCloud Drive, no move")
check(LibrarySync.enablePrompt(iCloudFolderExists: true, cloudFileExists: false) == .move, "empty iCloud moves the library")
check(LibrarySync.enablePrompt(iCloudFolderExists: true, cloudFileExists: true) == .askWhichToKeep, "two libraries ask")
do {
    let local = URL(fileURLWithPath: "/t/.library/bookmarks.json"), cloud = URL(fileURLWithPath: "/t/icloud/Library/bookmarks.json")
    let bl = URL(fileURLWithPath: "/t/.library/before.json"), bc = URL(fileURLWithPath: "/t/.library/replaced.json")
    check(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: bl, backupCloud: bc, prompt: .move, choice: .useThisMac)
        == [.copy(from: local, to: cloud), .verify(cloud, matches: local), .remove(local), .link(local, to: cloud)], "move copies, verifies, then links")
    check(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: bl, backupCloud: bc, prompt: .askWhichToKeep, choice: .useICloud)
        == [.copy(from: local, to: bl), .remove(local), .link(local, to: cloud)], "using iCloud backs up this Mac's file first")
    check(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: bl, backupCloud: bc, prompt: .askWhichToKeep, choice: .useThisMac)
        == [.copy(from: cloud, to: bc), .copy(from: local, to: cloud), .verify(cloud, matches: local), .remove(local), .link(local, to: cloud)], "replacing iCloud backs it up first")
    check(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: bl, backupCloud: bc, prompt: .askWhichToKeep, choice: .cancel).isEmpty, "cancel does nothing")
    check(LibrarySync.disableSteps(local: local, cloud: cloud)
        == [.remove(local), .copy(from: cloud, to: local), .verify(local, matches: cloud), .removeICloud(cloud)], "turning off verifies before removing the iCloud copy")
}

// Recently Deleted: tombstones, restore, delete immediately, and the 30-day purge
do {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let a = syncItem("a"), x = syncItem("x"), folder = syncItem("F", children: [x]), b = syncItem("b")
    var c = LibrarySync.Contents(live: [a, folder, b])
    LibrarySync.tombstone([a.id], in: &c, at: now)
    check(c.live.map(\.name) == ["F", "b"] && c.deleted.map(\.name) == ["a"], "a deleted item moves to Recently Deleted")
    check(c.deleted.first?.deletedDate == now && c.deleted.first?.deletedFrom == nil, "the deleted item keeps its date and no folder")
    LibrarySync.tombstone([x.id], in: &c, at: now)
    check(c.live[0].children?.isEmpty == true && c.deleted.last?.name == "x" && c.deleted.last?.deletedFrom == folder.id, "a deleted child remembers its folder")
    LibrarySync.restore([x.id], in: &c)
    check(c.live[0].children?.map(\.name) == ["x"] && c.deleted.map(\.name) == ["a"], "restore puts a child back in its folder")
    LibrarySync.tombstone([folder.id, x.id], in: &c, at: now)
    check(c.live.map(\.name) == ["b"] && c.deleted.map(\.name).contains("F") && c.deleted.first(where: { $0.name == "F" })?.children?.map(\.name) == ["x"],
          "a deleted folder takes its children, and a selected child is not deleted twice")
    LibrarySync.restore([x.id], in: &c)
    check(c.live.map(\.name) == ["b", "F"] && c.live.last?.children?.map(\.name) == ["x"], "restoring a child restores its folder with its children")
    LibrarySync.tombstone([folder.id], in: &c, at: now)
    LibrarySync.deleteImmediately([folder.id], in: &c)
    check(!c.deleted.contains { $0.name == "F" } && c.deleted.map(\.name) == ["a"], "delete immediately removes the subtree for good")
    var old = LibrarySync.Contents(live: [], deleted: [
        { var i = syncItem("old"); i.deletedDate = daysAgo(31, from: now); return i }(),
        { var i = syncItem("recent"); i.deletedDate = daysAgo(29, from: now); return i }(),
    ])
    LibrarySync.purge(&old, now: now)
    check(old.deleted.map(\.name) == ["recent"], "a tombstone older than 30 days is purged, a newer one is kept")
    let file = try! LibrarySync.encode(LibrarySync.Contents(live: [a], deleted: [c.deleted.first ?? a]))
    check(LibrarySync.decode(file)?.live.map(\.name) == ["a"] && LibrarySync.decode(file)?.deleted.count == 1, "the file keeps live items and tombstones apart on reading")
    check(LibrarySync.decode(Data(#"[{"id":"6F1E3C2A-0000-4000-8000-000000000001","name":"old","modified":"2024-01-01T00:00:00Z","url":"https://o.example.com"}]"#.utf8))?.live.map(\.name) == ["old"],
          "a file with the old merge stamp still loads")
}

// Conflicts: differences and the choices for each item
do {
    let id = UUID(), other = UUID(), third = UUID()
    let local = LibrarySync.Contents(live: [syncItem("A", id: id), syncItem("B", id: other)])
    let remote = LibrarySync.Contents(live: [syncItem("A2", id: id), syncItem("C", id: third)])
    let diffs = LibrarySync.differences(local: local, other: remote)
    check(diffs.count == 3 && diffs.contains { $0.id == other && $0.other == "Not in this version" }, "items on one side only, and changed items, are listed")
    check(LibrarySync.differences(local: local, other: local).isEmpty, "identical versions have no differences")
    check(LibrarySync.resolve(local: local, other: remote, preferring: .thisMac, choices: [:]) == local, "keeping this Mac's version keeps it exactly")
    check(LibrarySync.resolve(local: local, other: remote, preferring: .other, choices: [:]) == remote, "keeping the other version keeps it exactly")
    let picked = LibrarySync.resolve(local: local, other: remote, preferring: .thisMac, choices: [id: .other])
    check(picked.live.map(\.name) == ["A2", "B"], "a per-item choice takes the other version of that item only")
    let withTrash = LibrarySync.Contents(live: [syncItem("a", id: id)], deleted: [])
    var deletedOnOther = withTrash
    LibrarySync.tombstone([id], in: &deletedOnOther, at: Date(timeIntervalSince1970: 5))
    let kept = LibrarySync.resolve(local: withTrash, other: deletedOnOther, preferring: .thisMac, choices: [:])
    check(kept.live.map(\.name) == ["a"] && kept.deleted.isEmpty, "this Mac's live item stays live when the other Mac deleted it")
    let deletedFolder = LibrarySync.resolve(local: withTrash, other: deletedOnOther, preferring: .other, choices: [:])
    check(deletedFolder.live.isEmpty && deletedFolder.deleted.map(\.name) == ["a"], "keeping the other version keeps its deletion")
}

// Sync state from ubiquitous keys
check(LibrarySync.syncState(isUploading: false, isUploaded: true, downloading: .current) == .upToDate, "a current, uploaded file is up to date")
check(LibrarySync.syncState(isUploading: true, isUploaded: true, downloading: .current) == .uploading, "an uploading file shows uploading")
check(LibrarySync.syncState(isUploading: false, isUploaded: false, downloading: .current) == .uploading, "a file not uploaded yet shows uploading")
check(LibrarySync.syncState(isUploading: false, isUploaded: true, downloading: .notDownloaded) == .waiting, "a file not downloaded shows waiting")
check(LibrarySync.syncState(isUploading: false, isUploaded: true, downloading: nil) == .upToDate, "no download status is up to date")
check(LibrarySync.syncState(of: URL(fileURLWithPath: "/tmp/not-in-icloud-\(UUID().uuidString).json")) == nil, "a file outside iCloud Drive has no sync state")

// File steps and coordinated access on temporary folders
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("library-sync-check-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }
    let local = root.appendingPathComponent(".library/bookmarks.json")
    let cloud = root.appendingPathComponent("iCloud/Library/bookmarks.json")
    let before = root.appendingPathComponent(".library/bookmarks-before-iCloud.json")
    let replaced = root.appendingPathComponent(".library/bookmarks-iCloud-replaced.json")
    try! fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data("LOCAL".utf8).write(to: local)

    try! LibrarySync.run(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: before, backupCloud: replaced,
                                                 prompt: .move, choice: .useThisMac))
    check(LibrarySync.linkDestination(of: local) == cloud && (try? Data(contentsOf: cloud)) == Data("LOCAL".utf8), "moving links this Mac's file to iCloud")
    check(LibrarySync.isLinked(local) && !LibrarySync.isDanglingLink(local), "the link works")
    // A save writes to the link's destination, through the coordinator, so the link stays a link.
    try! LibrarySync.write(Data("SAVED".utf8), to: LibrarySync.linkDestination(of: local)!)
    check(LibrarySync.isLinked(local) && (try? LibrarySync.read(local)) == Data("SAVED".utf8), "a coordinated save through the destination keeps the link")
    try! LibrarySync.run(LibrarySync.disableSteps(local: local, cloud: cloud))
    check(!LibrarySync.isLinked(local) && (try? Data(contentsOf: local)) == Data("SAVED".utf8) && !fm.fileExists(atPath: cloud.path), "turning off leaves a real file and removes the iCloud copy")

    // Two libraries: iCloud is kept.
    try! LibrarySync.run(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: before, backupCloud: replaced,
                                                 prompt: .move, choice: .useThisMac))
    try! Data("LOCAL2".utf8).write(to: local)
    try! Data("CLOUD".utf8).write(to: cloud)
    try! LibrarySync.run(LibrarySync.enableSteps(local: local, cloud: cloud, backupLocal: before, backupCloud: replaced,
                                                 prompt: .askWhichToKeep, choice: .useICloud))
    check(LibrarySync.isLinked(local) && (try? Data(contentsOf: local)) == Data("CLOUD".utf8), "using the iCloud library links to it")
    check((try? Data(contentsOf: before)) != nil, "the replaced file is kept as a backup")

    // A copy that does not match stops the steps before anything is removed.
    let stray = root.appendingPathComponent("stray.json")
    try! Data("X".utf8).write(to: stray)
    var mismatch = false
    do { try LibrarySync.run([.verify(stray, matches: cloud)]) } catch { mismatch = true }
    check(mismatch, "a mismatch is an error")

    // The iCloud copy disappears, as after another Mac turned the option off.
    try! fm.removeItem(at: cloud)
    check(LibrarySync.isDanglingLink(local), "a link to a missing iCloud copy is dangling")
    try! Data("RECOVER".utf8).write(to: root.appendingPathComponent("iCloud/Library/bookmarks.json"))
    LibrarySync.recover(local: local, cloud: cloud)
    check(!LibrarySync.isLinked(local) && (try? Data(contentsOf: local)) == Data("RECOVER".utf8), "recovery copies the iCloud copy back to this Mac")
    check(LibrarySync.enablePrompt(iCloudFolderExists: true, cloudFileExists: false) == .move, "a missing iCloud copy is a move, not a read")
}
// ---- Pinned item lock: state transitions and the title and copy decisions. The Touch ID or password prompt
// itself needs a person at the keyboard, so these checks never run it. ----
var lockState = PinnedLock()
check(!lockState.isUnlocked, "a new session starts locked, so quitting clears the unlock")
let firstAttempt = lockState.generation
lockState.finishAuthentication(succeeded: false, startedAt: firstAttempt)
check(!lockState.isUnlocked, "a cancelled or failed prompt leaves the items locked")
lockState.finishAuthentication(succeeded: true, startedAt: firstAttempt)
check(lockState.isUnlocked, "a successful prompt unlocks")
lockState.finishAuthentication(succeeded: false, startedAt: firstAttempt)
check(lockState.isUnlocked, "unlocked stays unlocked: a cancelled prompt does not relock")
lockState.systemWillSleep()
check(!lockState.isUnlocked, "the Mac going to sleep locks the items")
lockState.finishAuthentication(succeeded: true, startedAt: firstAttempt)
check(!lockState.isUnlocked, "a prompt that began before sleep cannot unlock after it")
lockState.finishAuthentication(succeeded: true, startedAt: lockState.generation)
check(lockState.isUnlocked, "a prompt that begins after sleep unlocks")
lockState.lock()
check(!lockState.isUnlocked, "Lock Pinned Items locks again")
check(PinnedLock.access(pinned: true, required: true, unlocked: false) == .afterAuthentication, "a locked pinned item needs authentication to copy or show")
check(PinnedLock.access(pinned: true, required: true, unlocked: true) == .now, "an unlocked pinned item copies at once")
check(PinnedLock.access(pinned: false, required: true, unlocked: false) == .now, "unpinned history is never locked")
check(PinnedLock.access(pinned: true, required: false, unlocked: false) == .now, "with the setting off, pinned items are open")
check(PinnedLock.displayed("card 4111", pinned: true, required: true, unlocked: false) == "Pinned Item", "a locked pinned item's title is replaced")
check(PinnedLock.displayed("card 4111", pinned: true, required: true, unlocked: true) == "card 4111", "an unlocked pinned item's title is shown")
check(PinnedLock.displayed("notes", pinned: false, required: true, unlocked: false) == "notes", "an unpinned title is shown")
check(PinnedLock.displayed("notes", pinned: true, required: false, unlocked: false) == "notes", "the title is shown with the setting off")
// Touch ID and the Mac password may both be missing: enabling is refused, and a locked item explains instead of prompting.
check(LockAvailability.decide(canAuthenticate: true, enabling: true, needsAuthentication: false) == .available, "with Touch ID or a password, the setting turns on")
check(LockAvailability.decide(canAuthenticate: false, enabling: true, needsAuthentication: false) == .unavailableOnEnable, "with no password or Touch ID, the setting does not turn on")
check(LockAvailability.decide(canAuthenticate: false, enabling: false, needsAuthentication: true) == .unavailableOnUse, "a locked item with no password or Touch ID explains instead of prompting")
check(LockAvailability.decide(canAuthenticate: false, enabling: false, needsAuthentication: false) == .available, "turning the setting off or showing unpinned history needs no password")

// The app's setting decides what the shared lock hides. It is set back to off afterwards.
let sharedLock = ClipboardLock.shared
sharedLock.isRequired = true
var pinnedCopy = clip(.text, text: "a secret note")
pinnedCopy.pinned = true
check(sharedLock.isHidden(pinnedCopy) && sharedLock.title(for: pinnedCopy) == "Pinned Item" && sharedLock.menuTitle(for: pinnedCopy) == "Pinned Item",
      "with the setting on, a locked pinned item is hidden in lists and menus")
check(!sharedLock.isHidden(clip(.text, text: "an unpinned note")), "with the setting on, unpinned history is not hidden")
// Searching the history must not reveal a locked pinned item's text.
let searchFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-search-\(UUID().uuidString).json")
let searchKey = SymmetricKey(size: .bits256)
let searchPins = [PinnedFile.Clip(source: "Notes", date: Date(), representations: [["public.utf8-plain-text": Data("unlisted search words".utf8)]])]
try? JSONEncoder().encode(searchPins).write(to: searchFile)
let searchHistory = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-s-\(UUID().uuidString)")), file: searchFile, key: { searchKey })
// Pinned items load in the background, so wait for the load to finish before checking them. The main run loop is
// pumped meanwhile, since the load publishes its result on the main actor.
let searchLoadDeadline = Date().addingTimeInterval(10)
while !searchHistory.pinnedLoaded && Date() < searchLoadDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
check(searchHistory.pinnedLoaded && searchHistory.items.first?.pinned == true, "the pinned search fixture loads")
check(searchHistory.search("unlisted").isEmpty, "a locked pinned item is not found by search")
// A locked pinned item's Quick Open row and actions header show Pinned Item, not its text.
let lockedRow = QuickOpenResult(kind: .clip(pinnedCopy), id: "clip-locked")
check(lockedRow.displayTitle == "Pinned Item", "a locked pinned item's Quick Open row hides its text")
sharedLock.isRequired = false
check(QuickOpenResult(kind: .clip(pinnedCopy), id: "clip-shown").displayTitle == pinnedCopy.title, "with the setting off, the Quick Open row shows the title")
sharedLock.isRequired = false
check(searchHistory.search("unlisted").count == 1 && !sharedLock.isHidden(pinnedCopy), "with the setting off, the pinned item is found and shown")
try? FileManager.default.removeItem(at: searchFile)

// ---- row drops: which move a drop makes (pure) ----
do {
    let inner = LibraryItem(name: "Inner", url: "inner.example.com")
    let folder = LibraryItem(name: "Folder", children: [inner])
    let other = LibraryItem(name: "Other", url: "other.example.com")
    let divider = LibraryItem(name: "Divider", isDivider: true)
    let rows = [folder, other, divider]
    let one: Set<UUID> = [other.id]
    check(rowDrop(moving: one, onto: folder.id, in: rows, listSorted: false) == .moveInto(folder.id), "drop on a folder moves into it")
    check(rowDrop(moving: one, onto: folder.id, in: rows, listSorted: true) == .moveInto(folder.id), "drop on a folder moves into it when sorted")
    check(rowDrop(moving: one, onto: divider.id, in: rows, listSorted: false) == .moveBefore(divider.id), "drop on a row, unsorted, goes before it")
    check(rowDrop(moving: one, onto: other.id, in: rows, listSorted: false) == .ignore, "drop onto itself is ignored")
    check(rowDrop(moving: one, onto: divider.id, in: rows, listSorted: true) == .ignore, "drop on a row while sorted does not reorder")
    check(rowDrop(moving: one, onto: nil, in: rows, listSorted: true) == .moveToTopLevel, "drop on empty space goes to the top level")
    check(rowDrop(moving: [], onto: nil, in: rows, listSorted: false) == .ignore, "nothing dragged is ignored")
    check(rowDrop(moving: [folder.id], onto: inner.id, in: rows, listSorted: false) == .ignore, "folder dropped into its own child is rejected")
    check(rowDrop(moving: [folder.id], onto: inner.id, in: rows, listSorted: true) == .ignore, "folder dropped into its own child is rejected when sorted")
    check(rowDrop(moving: [folder.id], onto: folder.id, in: rows, listSorted: false) == .ignore, "folder dropped onto itself is rejected")
    check(rowDrop(moving: [inner.id], onto: folder.id, in: rows, listSorted: false) == .moveInto(folder.id), "a child dropped on its own folder moves into it")
    check(rowDrop(moving: [other.id], onto: inner.id, in: rows, listSorted: false) == .moveBefore(inner.id), "a row dropped on a folder's child goes before the child")
    check(rowDrop(moving: [other.id], onto: UUID(), in: rows, listSorted: false) == .ignore, "a target that is not in the library is ignored")
}
// ---- notes ----
check(LibraryItem(name: "N", url: "x.example.com").note == nil, "a new item has no note")
let noteOldJSON = Data(#"{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","name":"Jira","url":"x.example.com"}"#.utf8)
check((try? JSONDecoder().decode(LibraryItem.self, from: noteOldJSON))?.note == nil, "a file without a note loads")
check(LibraryItem.cleanNote("  first line\nsecond  \n") == "first line\nsecond", "a note is trimmed, keeping its inner lines")
check(LibraryItem.cleanNote(" \n\t ") == nil && LibraryItem.cleanNote(nil) == nil, "a blank note is no note")
var noted = LibraryItem(name: "Docs", url: "https://docs.example.com")
noted.note = "  Read section 3\nthen the FAQ "
check(noted.noteText == "Read section 3\nthen the FAQ", "noteText trims the note")
check(noted.spotlightDescription == "https://docs.example.com\nRead section 3\nthen the FAQ", "Spotlight shows the note after the target")
noted.note = "   "
check(noted.noteText == nil && noted.spotlightDescription == "https://docs.example.com", "a blank note is left out of Spotlight")
check(LibraryItem(name: "Ask", command: "make").spotlightDescription == "make", "a command's Spotlight description is its command")
check(LibraryItem(name: "Folder", children: []).spotlightDescription == nil, "no target and no note gives no Spotlight description")
var notedTrip = LibraryItem(name: "Docs", url: "https://docs.example.com", note: "a\nb")
if let data = try? JSONEncoder().encode(notedTrip), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.note == "a\nb" && back == notedTrip, "a note round-trips through the file")
} else { check(false, "a note round-trips through the file") }
notedTrip.note = nil
check(notedTrip.noteText == nil, "clearing the note clears it")
let noteSearch = [LibraryItem(name: "Docs", url: "https://docs.example.com", note: "Read section 3\nthen the FAQ")]
check(QuickOpenResult.search("docs", in: noteSearch, counts: [:]).first?.noteLine == "Read section 3 then the FAQ", "Quick Open shows the note on one line")
check(QuickOpenResult.search("docs", in: [LibraryItem(name: "Docs", url: "https://docs.example.com")], counts: [:]).first?.noteLine == nil, "Quick Open shows no note line without a note")
check(QuickOpenResult.search("", in: noteSearch, counts: [:]).first?.noteLine != nil, "a note shows in the browse list too")

// ---- Reading List ----
let readA = LibraryItem(name: "A", url: "https://a.example.com", readLater: .read)
let readB = LibraryItem(name: "B", url: "https://b.example.com")
let readC = LibraryItem(name: "C", url: "https://c.example.com", readLater: .unread)
let readD = LibraryItem(name: "D", url: "https://d.example.com", readLater: .read)
let readE = LibraryItem(name: "E", url: "https://e.example.com", readLater: .unread)
check(ReadingList.ordered([readA, readB, readC, readD, readE]).map(\.name) == ["C", "E", "A", "D"], "Reading List: unread first, then read, each in tree order")
check(ReadingList.ordered([readB]).isEmpty && ReadingList.ordered([]).isEmpty, "Reading List: items not in the list are left out")
check(ReadingList.state(after: .add, from: nil) == .unread && ReadingList.state(after: .add, from: .read) == .read, "adding gives unread, and keeps a state already there")
check(ReadingList.state(after: .markRead, from: .unread) == .read && ReadingList.state(after: .markUnread, from: .read) == .unread, "marking read and unread changes an item in the list")
check(ReadingList.state(after: .markRead, from: nil) == nil && ReadingList.state(after: .markUnread, from: nil) == nil, "marking never adds an item to the list")
check(ReadingList.state(after: .remove, from: .unread) == nil && ReadingList.state(after: .remove, from: .read) == nil, "removing clears the state")
check(readB.canReadLater && !LibraryItem(name: "Folder", children: []).canReadLater, "only bookmarks can be listed")
check(LibraryItem(name: "T", url: "x.example.com/{}").canReadLater == false && LibraryItem(name: "App", appPath: "/Applications/Safari.app").canReadLater == false, "templates and apps cannot be listed")
check(ReadingList.Action.add.title == "Add to Reading List" && ReadingList.Action.remove.title == "Remove from Reading List", "Reading List action names")
let readOldJSON = Data(#"{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","name":"Jira","url":"x.example.com"}"#.utf8)
check((try? JSONDecoder().decode(LibraryItem.self, from: readOldJSON))?.readLater == nil, "a file without a Reading List state loads as not listed")
if let data = try? JSONEncoder().encode(readA), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.readLater == .read && back == readA, "a Reading List state round-trips through the file")
} else { check(false, "a Reading List state round-trips through the file") }
// ---- link check: rules ----
let linkNow = Date(timeIntervalSince1970: 1_800_000_000)
func linkDate(hoursAgo: Double) -> Date { linkNow.addingTimeInterval(-hoursAgo * 3600) }
check(LinkCheck.kind(forHTTPCode: 200) == .ok && LinkCheck.kind(forHTTPCode: 204) == .ok, "2xx is ok")
check(LinkCheck.kind(forHTTPCode: 301) == .ok && LinkCheck.kind(forHTTPCode: 302) == .ok && LinkCheck.kind(forHTTPCode: 399) == .ok, "3xx is ok")
check(LinkCheck.kind(forHTTPCode: 400) == .broken && LinkCheck.kind(forHTTPCode: 404) == .broken && LinkCheck.kind(forHTTPCode: 499) == .broken, "4xx is broken")
check(LinkCheck.kind(forHTTPCode: 500) == .broken && LinkCheck.kind(forHTTPCode: 503) == .broken && LinkCheck.kind(forHTTPCode: 599) == .broken, "5xx is broken")
check(LinkCheck.kind(forHTTPCode: 100) == .unreachable && LinkCheck.kind(forHTTPCode: 600) == .unreachable && LinkCheck.kind(forHTTPCode: 0) == .unreachable, "codes outside 200-599 give no answer")
check(LinkCheck.outcome(statusCode: nil, redirectRefused: false) == .unreachable, "no response is unreachable, not broken")
check(LinkCheck.outcome(statusCode: 302, redirectRefused: true) == .unreachable, "a refused redirect is unreachable, not ok")
check(LinkCheck.outcome(statusCode: 200, redirectRefused: false) == .ok && LinkCheck.outcome(statusCode: 404, redirectRefused: false) == .broken, "a finished response uses its code")
check(LinkCheck.retriesWithGET(afterHEAD: 403) && LinkCheck.retriesWithGET(afterHEAD: 405) && LinkCheck.retriesWithGET(afterHEAD: 501), "a HEAD refused with 403, 405, or 501 is asked again with GET")
check(!LinkCheck.retriesWithGET(afterHEAD: 200) && !LinkCheck.retriesWithGET(afterHEAD: 302) && !LinkCheck.retriesWithGET(afterHEAD: 404) && !LinkCheck.retriesWithGET(afterHEAD: 500) && !LinkCheck.retriesWithGET(afterHEAD: nil), "other HEAD answers, and no answer, are final")
check(LinkCheck.retriesWithGET(afterHEAD: 405) && LinkCheck.outcome(statusCode: 200, redirectRefused: false) == .ok && LinkCheck.outcome(statusCode: 404, redirectRefused: false) == .broken, "a HEAD refused with 405 takes the status of the GET that follows")
check(LinkCheck.followsRedirect(after: 0, to: URL(string: "https://example.com/next")) && LinkCheck.followsRedirect(after: 4, to: URL(string: "http://example.com/")), "redirects up to five are followed")
check(!LinkCheck.followsRedirect(after: 5, to: URL(string: "https://example.com/next")), "the sixth redirect is refused")
check(!LinkCheck.followsRedirect(after: 0, to: URL(string: "file:///etc/passwd")) && !LinkCheck.followsRedirect(after: 0, to: URL(string: "ftp://example.com/")) && !LinkCheck.followsRedirect(after: 0, to: nil), "redirects to non-web addresses are refused")
check(!LinkCheck.followsRedirect(after: 0, from: URL(string: "https://example.com/a"), to: URL(string: "http://example.com/b")), "a link check never follows https to http")
check(LinkCheck.followsRedirect(after: 0, from: URL(string: "http://example.com/a"), to: URL(string: "https://example.com/b")), "a redirect up to https is followed")
check(WebFetch.isDowngrade(from: URL(string: "https://a.example.com"), to: URL(string: "HTTP://a.example.com")) && !WebFetch.isDowngrade(from: URL(string: "http://a.example.com"), to: URL(string: "https://a.example.com")) && !WebFetch.isDowngrade(from: URL(string: "https://a.example.com"), to: URL(string: "https://b.example.com")), "only https to http is a downgrade")
check(LinkCheck.isRecentlyChecked(linkDate(hoursAgo: 0), now: linkNow) && LinkCheck.isRecentlyChecked(linkDate(hoursAgo: 23.9), now: linkNow), "a check within 24 hours is recent")
check(!LinkCheck.isRecentlyChecked(linkDate(hoursAgo: 24), now: linkNow) && !LinkCheck.isRecentlyChecked(linkDate(hoursAgo: 25), now: linkNow), "a check 24 hours or more ago is not recent")
check(!LinkCheck.isRecentlyChecked(nil, now: linkNow) && !LinkCheck.isRecentlyChecked(linkNow.addingTimeInterval(3600), now: linkNow), "never checked, or checked in the future, is not recent")
check(LinkCheck.isDailyCheckDue(now: linkNow, lastRun: nil), "a daily check with no past run is due")
check(!LinkCheck.isDailyCheckDue(now: linkNow, lastRun: linkDate(hoursAgo: 23.9)), "a daily check less than a day after the last is not due")
check(LinkCheck.isDailyCheckDue(now: linkNow, lastRun: linkDate(hoursAgo: 24)) && LinkCheck.isDailyCheckDue(now: linkNow, lastRun: linkNow.addingTimeInterval(60)), "a day later, or a last run in the future, is due")
check(LinkCheck.secondsUntilDailyCheck(now: linkNow, lastRun: nil) == 0 && LinkCheck.secondsUntilDailyCheck(now: linkNow, lastRun: linkDate(hoursAgo: 1)) == 23 * 3600, "the wait is the rest of the day")
check(LinkCheck.startCount(running: 0, pending: 10) == 4 && LinkCheck.startCount(running: 3, pending: 10) == 1 && LinkCheck.startCount(running: 4, pending: 10) == 0, "at most four requests run at once")
check(LinkCheck.startCount(running: 0, pending: 2) == 2 && LinkCheck.startCount(running: 0, pending: 0) == 0 && LinkCheck.startCount(running: 6, pending: 3) == 0, "no more requests than are waiting")
let linkPage = LibraryItem(name: "Page", url: "https://example.com/page")
let linkDivider = LibraryItem(name: "Divider", isDivider: true)
let linkApp = LibraryItem(name: "Safari", appPath: "/Applications/Safari.app")
let linkCommand = LibraryItem(name: "Make", command: "make")
let linkTemplate = LibraryItem(name: "Jira", url: "tickets.example.com/browse/{}")
let linkFolder = LibraryItem(name: "Folder", children: [])
let linkBad = LibraryItem(name: "Bad scheme", url: "file:///tmp/x")
check(LinkCheck.isCheckable(linkPage) && LinkCheck.isCheckable(LibraryItem(name: "Bare", url: "example.com")), "a web bookmark is checkable, with or without a scheme")
check(!LinkCheck.isCheckable(linkDivider) && !LinkCheck.isCheckable(linkApp) && !LinkCheck.isCheckable(linkCommand), "dividers, apps, and commands are not checked")
check(!LinkCheck.isCheckable(linkTemplate) && !LinkCheck.isCheckable(linkFolder) && !LinkCheck.isCheckable(linkBad), "templates, folders, and non-web addresses are not checked")
let linkShared = LibraryItem(name: "Again", url: "https://example.com/page", linkStatus: LinkStatus(kind: .ok, checked: linkDate(hoursAgo: 2)))
let linkOld = LibraryItem(name: "Old", url: "https://old.example.com/", linkStatus: LinkStatus(kind: .broken, checked: linkDate(hoursAgo: 30)))
let linkDue = LinkCheck.itemsToCheck([linkPage, linkOld, linkDivider, linkApp, linkTemplate], now: linkNow).map(\.name)
check(linkDue == ["Page", "Old"], "due: an unchecked and an old bookmark, not dividers, apps, or templates: \(linkDue)")
check(LinkCheck.itemsToCheck([linkPage, linkShared], now: linkNow).isEmpty, "a bookmark sharing an address checked in the last 24 hours is skipped with it")
check(LinkCheck.itemsToCheck([linkOld], now: linkNow).count == 1, "an address checked 30 hours ago is due again")
let linkPlain = LibraryItem(name: "Plain", url: "https://example.com/page")
check(LinkCheck.key(for: linkPlain) == "https://example.com/page" && LinkCheck.key(for: linkApp) == nil, "the request key is the address")
// The record decodes from a file without the field, and round-trips with it.
let linkOldFile = Data(#"{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","name":"Old","url":"https://example.com/"}"#.utf8)
let linkOldItem = try? JSONDecoder().decode(LibraryItem.self, from: linkOldFile)
check(linkOldItem?.linkStatus == nil, "a file without linkStatus loads, with no status")
var linkWithStatus = linkOldItem ?? linkPlain
linkWithStatus.linkStatus = LinkStatus(kind: .unreachable, checked: linkNow)
if let data = try? JSONEncoder().encode(linkWithStatus), let back = try? JSONDecoder().decode(LibraryItem.self, from: data) {
    check(back.linkStatus == LinkStatus(kind: .unreachable, checked: linkNow), "the status round-trips through the file")
} else {
    check(false, "the status round-trips through the file")
}
check(!String(decoding: (try? JSONEncoder().encode(linkOldItem ?? linkPlain)) ?? Data(), as: UTF8.self).contains("linkStatus"), "an item without a status writes no linkStatus key")
check(!LinkCheck.isCheckable(LibraryItem(name: "Empty", url: "")) && !LinkCheck.isCheckable(LibraryItem(name: "Space", url: "   ")), "a blank address is not checked")
// ---- page titles for new bookmarks: fixed HTML, no network ----
check(PageTitle.extract(from: "<html><head><title>Example Domain</title></head></html>") == "Example Domain", "a normal title")
check(PageTitle.extract(from: "<TITLE lang=\"en\">Upper case tag</Title >") == "Upper case tag", "the tag name and attributes ignore case and spacing")
check(PageTitle.extract(from: "<title>Tom &amp; Jerry &lt;3 &#39;quoted&#39; &#x263A; &copy; 2026</title>") == "Tom & Jerry <3 'quoted' \u{263A} \u{00A9} 2026",
      "entities are decoded")
check(PageTitle.extract(from: "<title>&amp;lt; &unknown; &#xZZ;</title>") == "&lt; &unknown; &#xZZ;", "an entity is decoded once, and unknown ones stay as written")
check(PageTitle.extract(from: "<head>\n<title>\n    Weekly\n   Report  \n</title>") == "Weekly Report", "a title split over lines is joined with single spaces")
check(PageTitle.extract(from: "<html><body>No title here</body></html>") == nil, "a page with no title has none")
check(PageTitle.extract(from: "<title>   \n  </title>") == nil, "an empty title is none, so the host stays")
check(PageTitle.extract(from: "<title>First</title><title>Second</title>") == "First", "the first title wins")
let earlyTitle = Data("<html><head><title>Early</title></head><body>".utf8) + Data(repeating: UInt8(ascii: "x"), count: 70_000)
check(PageTitle.title(in: earlyTitle) == "Early", "a title within the first 64 KB is read")
let lateTitle = Data("<html><head>".utf8) + Data(repeating: UInt8(ascii: "x"), count: 70_000) + Data("<title>Late</title>".utf8)
check(PageTitle.title(in: lateTitle) == nil, "a title past the first 64 KB is not read")
let cutInside = Data("<title>Cut".utf8) + Data(repeating: UInt8(ascii: "x"), count: PageTitle.readLimit) + Data("</title>".utf8)
check(PageTitle.title(in: cutInside) == nil, "a title cut off by the limit is not read")
// The 64 KB cut lands inside a two-byte character after the title, which must not hide the title.
let splitCharacter = Data("<title>Ok</title>".utf8) + Data(Array(repeating: [UInt8(0xC3), UInt8(0xA9)], count: 40_000).flatMap { $0 })
check(PageTitle.title(in: splitCharacter) == "Ok", "a character cut by the limit does not hide the title")
check(PageTitle.collapsingWhitespace("  a \t b\n\nc  ") == "a b c", "whitespace collapses and is trimmed")

// ---- Hostile pages: the scans are bounded, so unclosed tags cannot stall a favicon load ----
let hostileStart = Date()
check(Favicon.iconHref(in: String(repeating: "<link ", count: 40_000)) == nil, "unclosed link tags give no icon")
check(PageTitle.extract(from: String(repeating: "<title>", count: 10_000)) == nil && PageTitle.extract(from: String(repeating: "<title ", count: 10_000)) == nil, "unclosed title tags give no title")
check(Date().timeIntervalSince(hostileStart) < 2, "hostile markup is scanned in bounded time")
check(Favicon.iconHref(in: "<link rel=\"icon\" href=\"/a.png\">") == "/a.png", "a normal icon link is read")
check(Favicon.iconHref(in: String(repeating: " ", count: 70_000) + "<link rel='icon' href='/b'>") == nil, "an icon link past the first 64 KB is not read")

// ---- Most Used and Recently Opened: largest first, never opened last, ties in tree order ----
let orderA = LibraryItem(name: "A", url: "https://a.example.com")
let orderB = LibraryItem(name: "B", url: "https://b.example.com")
let orderC = LibraryItem(name: "C", url: "https://c.example.com")
let orderD = LibraryItem(name: "D", url: "https://d.example.com")
let orderE = LibraryItem(name: "E", url: "https://e.example.com")
let treeOrder = [orderA, orderB, orderC, orderD, orderE]
func names(_ items: [LibraryItem]) -> [String] { items.map(\.name) }
let counts = [orderB.id.uuidString: 2, orderC.id.uuidString: 5, orderD.id.uuidString: 2, orderE.id.uuidString: 0]
check(names(UsageOrder.mostUsed(treeOrder, counts: counts)) == ["C", "B", "D", "A", "E"],
      "most used: largest first, ties keep tree order, never opened and zero last in tree order")
check(names(UsageOrder.mostUsed(treeOrder, counts: [:])) == ["A", "B", "C", "D", "E"], "nothing opened keeps the tree order")
check(names(UsageOrder.mostUsed([], counts: counts)).isEmpty, "no items give an empty order")
let opened: [String: Date] = [
    orderB.id.uuidString: Date(timeIntervalSince1970: 100),
    orderC.id.uuidString: Date(timeIntervalSince1970: 300),
    orderD.id.uuidString: Date(timeIntervalSince1970: 100),
]
check(names(UsageOrder.recentlyOpened(treeOrder, opened: opened)) == ["C", "B", "D", "A", "E"],
      "recently opened: most recent first, equal dates keep tree order, never opened last")
check(names(UsageOrder.recentlyOpened(treeOrder, opened: [:])) == ["A", "B", "C", "D", "E"], "nothing opened keeps the tree order by date too")
// ---- clipboard history kept across restarts. The pure rules first, then a private pasteboard, a temporary folder and a test key ----
func historyFixture(_ digest: String, _ kind: ClipItem.Kind = .text, bytes: Int = 10, date: Date, pinned: Bool = false) -> ClipItem {
    ClipItem(representations: [], digest: digest, kind: kind, title: digest, plainText: nil, link: nil, thumbnail: nil,
             gifURL: nil, fileURLs: [], byteCount: bytes, date: date, pinned: pinned)
}
do {
    // The save decision: the setting, pinned items, and the image size limits.
    check(!HistoryRestart.saves(kind: .text, byteCount: 10, pinned: false, keeps: false), "a copy is not saved when the setting is off")
    check(HistoryRestart.saves(kind: .text, byteCount: 10, pinned: false, keeps: true), "an unpinned copy is saved when the setting is on")
    check(!HistoryRestart.saves(kind: .text, byteCount: 10, pinned: true, keeps: true), "a pinned item is left to clipboard.json")
    check(HistoryRestart.saves(kind: .image, byteCount: HistoryRestart.maxSavedImageBytes, pinned: false, keeps: true), "an image of 5 MB is saved")
    check(!HistoryRestart.saves(kind: .image, byteCount: HistoryRestart.maxSavedImageBytes + 1, pinned: false, keeps: true), "an image over 5 MB is not saved")
    check(HistoryRestart.saves(kind: .text, byteCount: HistoryRestart.maxSavedImageBytes + 1, pinned: false, keeps: true), "the 5 MB limit is for images only")
    check(!HistoryRestart.saves(kind: .file, byteCount: ClipboardHistory.maxItemBytes + 1, pinned: false, keeps: true), "an item over 25 MB is not saved")
    check(!HistoryRestart.saves(kind: .image, byteCount: ClipboardHistory.maxItemBytes + 1, pinned: false, keeps: true), "an image over 25 MB is not saved")

    // The merge: pins first, then the restored items newest first, each digest once.
    let base = Date(timeIntervalSince1970: 1_000)
    let pin = historyFixture("pin", date: base.addingTimeInterval(100), pinned: true)
    let newCopy = historyFixture("copy", date: base.addingTimeInterval(300))
    let restoredA = historyFixture("a", date: base.addingTimeInterval(200))
    let restoredB = historyFixture("b", date: base.addingTimeInterval(50))
    let restoredPin = historyFixture("pin", date: base.addingTimeInterval(400))
    let merged = HistoryRestart.merge([newCopy, pin], restored: [restoredB, restoredPin, restoredA])
    check((merged.filter(\.pinned) + merged.filter { !$0.pinned }).map(\.digest) == ["pin", "copy", "a", "b"],
          "restored items follow the pins, newest first, and a pinned digest is not restored again")
    check(merged.count == 4, "a restored item already present is skipped")

    // The limits: the oldest unpinned items go first, and pins are never removed.
    var many: [ClipItem] = (0..<52).map { historyFixture("n\($0)", date: base.addingTimeInterval(Double(100 - $0))) }
    many.append(historyFixture("old pin", date: base, pinned: true))
    let counted = HistoryRestart.limited(many, maxItems: 50, maxTotalBytes: 1_000_000)
    check(counted.filter { !$0.pinned }.count == 50 && counted.first?.digest == "n0" && counted.last?.digest == "old pin",
          "the newest 50 unpinned items are kept and the pin stays")
    let sized = [historyFixture("x", bytes: 100, date: base.addingTimeInterval(20)),
                 historyFixture("y", bytes: 100, date: base.addingTimeInterval(10)),
                 historyFixture("z", bytes: 100, date: base)]
    check(HistoryRestart.limited(sized, maxItems: 50, maxTotalBytes: 250).map(\.digest) == ["x", "y"], "the size limit drops the oldest")

    // The launch decision: the newest restored item, only with both settings on and no copy since launch.
    check(HistoryRestart.latest(in: [restoredB, restoredA])?.digest == "a", "the newest restored item is the latest")
    check(HistoryRestart.latest(in: []) == nil, "with nothing restored there is no latest item")
    check(HistoryRestart.copiesLatestAtLaunch(keeps: true, restoresLatest: true, latest: restoredA, copiedSinceLaunch: false),
          "the latest item is copied at launch when both settings are on")
    check(!HistoryRestart.copiesLatestAtLaunch(keeps: false, restoresLatest: true, latest: restoredA, copiedSinceLaunch: false), "not copied when history is not kept")
    check(!HistoryRestart.copiesLatestAtLaunch(keeps: true, restoresLatest: false, latest: restoredA, copiedSinceLaunch: false), "not copied when the option is off")
    check(!HistoryRestart.copiesLatestAtLaunch(keeps: true, restoresLatest: true, latest: nil, copiedSinceLaunch: false), "not copied when nothing was restored")
    check(!HistoryRestart.copiesLatestAtLaunch(keeps: true, restoresLatest: true, latest: restoredA, copiedSinceLaunch: true), "a copy made since launch is not replaced")

    // The file: sealed with the key, never read as plain text, and damage is reported rather than read.
    let historyKey = SymmetricKey(size: .bits256)
    let historySample = [PinnedFile.Clip(source: "Notes", date: base, representations: [["public.utf8-plain-text": Data("history secret".utf8)]])]
    if let sealed = try? HistoryFile.encode(historySample, key: historyKey) {
        check(sealed.range(of: Data("history secret".utf8)) == nil && sealed.range(of: Data("public.utf8-plain-text".utf8)) == nil,
              "the history file hides text and type names")
        if case .clips(let back) = HistoryFile.read(sealed, key: historyKey) {
            check(back.count == 1 && back[0].source == "Notes", "the history file reads back with its key")
        } else { check(false, "the history file reads back with its key") }
        if case .unreadable = HistoryFile.read(sealed, key: SymmetricKey(size: .bits256)) {} else { check(false, "the history file needs its own key") }
        if case .unreadable = HistoryFile.read(sealed, key: nil) {} else { check(false, "the history file is unreadable with no key") }
    } else { check(false, "encode the history file") }
    if case .unreadable = HistoryFile.read((try? JSONEncoder().encode(historySample)) ?? Data(), key: historyKey) {} else {
        check(false, "plain JSON is never read as history")
    }
    if case .unreadable = HistoryFile.read(Data(repeating: 0x43, count: 80), key: historyKey) {} else { check(false, "a damaged history file is unreadable") }
}

// The history on disk: a private pasteboard, a folder in the temporary directory and a test key. The Keychain and
// ~/.library are never touched.
MainActor.assumeIsolated {
    let keyH = SymmetricKey(size: .bits256)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-history-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let historyURL = folder.appendingPathComponent("clipboard-history.json")
    let damagedURL = folder.appendingPathComponent("clipboard-history-damaged.bin")
    let pinnedURL = folder.appendingPathComponent("clipboard.json")
    let otherPinnedURL = folder.appendingPathComponent("other-clipboard.json")
    @MainActor func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    @MainActor func waitFor(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    @MainActor func makeBoard() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("library-checks-h-\(UUID().uuidString)")) }
    @MainActor func copyText(_ text: String, on pasteboard: NSPasteboard, into target: ClipboardHistory) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        pasteboard.writeObjects([item])
        target.poll()
        waitFor { target.pendingCaptures == 0 }
    }
    @MainActor func savedClips(_ url: URL, key: SymmetricKey?) -> [PinnedFile.Clip]? {
        guard let data = try? Data(contentsOf: url), case .clips(let clips) = HistoryFile.read(data, key: key) else { return nil }
        return clips
    }
    @MainActor func keepOn(_ on: Bool) { UserDefaults.standard.set(on, forKey: "clipboardKeepsAcrossRestarts") }

    // The defaults are off, so the checks start from them.
    UserDefaults.standard.removeObject(forKey: "clipboardKeepsAcrossRestarts")
    UserDefaults.standard.removeObject(forKey: "clipboardRestoresLatest")

    // Off: nothing is saved.
    keepOn(false)
    let offBoard = makeBoard()
    let off = ClipboardHistory(pasteboard: offBoard, file: pinnedURL, historyFile: historyURL, key: { keyH })
    copyText("off copy", on: offBoard, into: off)
    off.flushHistory()
    ClipboardHistory.waitForSaves()
    check(!exists(historyURL), "with the setting off, no history file is written")

    // On: a copy is saved about a second later, sealed and private. A pinned item is left out of the history file.
    keepOn(true)
    let firstBoard = makeBoard()
    let first = ClipboardHistory(pasteboard: firstBoard, file: pinnedURL, historyFile: historyURL, key: { keyH })
    waitFor { first.historyLoaded && first.pinnedLoaded }
    check(first.keepsAcrossRestarts && first.historyLoaded, "a launch with the setting on loads the history")
    first.restoresLatestAtLaunch = true
    copyText("keep me", on: firstBoard, into: first)
    copyText("second copy", on: firstBoard, into: first)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    ClipboardHistory.waitForSaves()
    check(exists(historyURL), "a copy is saved about a second later, without quitting")
    let mode = (try? FileManager.default.attributesOfItem(atPath: historyURL.path))?[.posixPermissions] as? NSNumber
    check(mode?.intValue == 0o600, "the history file is readable only by this user")
    let savedBytes = (try? Data(contentsOf: historyURL)) ?? Data()
    check(savedBytes.range(of: Data("keep me".utf8)) == nil, "the saved history hides the text")
    check(savedClips(historyURL, key: keyH)?.count == 2, "both unpinned copies are saved")
    if let kept = first.items.first(where: { $0.title == "keep me" }) { first.togglePin(kept) }
    ClipboardHistory.waitForSaves()
    let pinnedBytes = (try? Data(contentsOf: pinnedURL)) ?? Data()
    check(!pinnedBytes.isEmpty, "pinning writes clipboard.json")
    first.flushHistory()
    ClipboardHistory.waitForSaves()
    check(savedClips(historyURL, key: keyH)?.count == 1, "a pinned item is left out of the history file")

    // Restart: the history comes back after the pins, and the newest unpinned item goes on the clipboard.
    let secondBoard = makeBoard()
    keepOn(true)
    UserDefaults.standard.set(true, forKey: "clipboardRestoresLatest")
    let restarted = ClipboardHistory(pasteboard: secondBoard, file: pinnedURL, historyFile: historyURL, key: { keyH })
    waitFor { restarted.historyLoaded && restarted.pinnedLoaded }
    check(restarted.displayOrder.map(\.title) == ["keep me", "second copy"], "history returns after the pins, pins first")
    check(restarted.items.count == 2, "the restored items are not doubled")
    check(secondBoard.string(forType: .string) == "second copy", "the newest restored item is on the clipboard at launch")
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    check(restarted.items.count == 2, "the launch copy is not recorded a second time")

    // Turning the setting off deletes the history and stops saving. The latest-item option turns off with it.
    restarted.keepsAcrossRestarts = false
    ClipboardHistory.waitForSaves()
    check(!exists(historyURL), "turning the setting off deletes the saved history")
    check(!restarted.restoresLatestAtLaunch, "turning the setting off also turns off the latest item")
    copyText("after off", on: secondBoard, into: restarted)
    restarted.flushHistory()
    ClipboardHistory.waitForSaves()
    check(!exists(historyURL), "with the setting off, copies are not saved")

    // Turning it on again does not change the pinned items.
    restarted.keepsAcrossRestarts = true
    restarted.flushHistory()
    ClipboardHistory.waitForSaves()
    check((try? Data(contentsOf: pinnedURL)) == pinnedBytes, "turning the setting on does not change pinned items")
    check(savedClips(historyURL, key: keyH)?.count == 2, "turning it on saves the unpinned history again")

    // A missing key: nothing is restored, and nothing is written over the saved file.
    let sealedBefore = (try? Data(contentsOf: historyURL)) ?? Data()
    keepOn(true)
    let lockedBoard = makeBoard()
    let locked = ClipboardHistory(pasteboard: lockedBoard, file: otherPinnedURL, historyFile: historyURL, key: { throw ClipboardKey.KeychainError(status: -1) })
    waitFor { locked.historyLoaded }
    check(locked.items.isEmpty, "with no key, no history is restored")
    copyText("locked copy", on: lockedBoard, into: locked)
    locked.flushHistory()
    ClipboardHistory.waitForSaves()
    check((try? Data(contentsOf: historyURL)) == sealedBefore, "with no key, the history file is left as it was")
    locked.keepsAcrossRestarts = false
    ClipboardHistory.waitForSaves()

    // A damaged history file is moved aside, not read, and the app starts with no history.
    try? Data(repeating: 0x44, count: 80).write(to: historyURL)
    keepOn(true)
    let damagedBoard = makeBoard()
    let damaged = ClipboardHistory(pasteboard: damagedBoard, file: otherPinnedURL, historyFile: historyURL, key: { keyH })
    waitFor { damaged.historyLoaded }
    check(damaged.items.isEmpty && !exists(historyURL) && exists(damagedURL), "a damaged history file is moved aside")
    damaged.keepsAcrossRestarts = false
    ClipboardHistory.waitForSaves()

    // Private copies and images over 5 MB are never saved, and the rest is.
    keepOn(true)
    let privateBoard = makeBoard()
    let privateHistory = ClipboardHistory(pasteboard: privateBoard, file: otherPinnedURL, historyFile: historyURL, key: { keyH })
    waitFor { privateHistory.historyLoaded }
    privateBoard.clearContents()
    let secret = NSPasteboardItem()
    secret.setString("private secret", forType: .string)
    secret.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    privateBoard.writeObjects([secret])
    privateHistory.poll()
    check(privateHistory.items.isEmpty, "a private copy is never recorded")
    copyText("visible copy", on: privateBoard, into: privateHistory)
    privateBoard.clearContents()
    let picture = NSPasteboardItem()
    picture.setData(Data(repeating: 0x2A, count: HistoryRestart.maxSavedImageBytes + 1_000_000), forType: .png)
    privateBoard.writeObjects([picture])
    privateHistory.poll()
    waitFor { privateHistory.pendingCaptures == 0 }
    check(privateHistory.items.contains { $0.kind == .image }, "a large picture is in the list while it is open")
    privateHistory.flushHistory()
    ClipboardHistory.waitForSaves()
    let privateSaved = savedClips(historyURL, key: keyH) ?? []
    check(privateSaved.count == 1 && privateSaved.first?.representations.first?["public.utf8-plain-text"] == Data("visible copy".utf8),
          "only the visible text is saved, not the private copy or the large picture")

    // Clear History while the history file is still loading (the key is held up) stays cleared: the saved clips do not come back.
    keepOn(true)
    let clearURL = folder.appendingPathComponent("clear-history.json")
    let seedClearBoard = makeBoard()
    let seedClear = ClipboardHistory(pasteboard: seedClearBoard, file: nil, historyFile: clearURL, key: { keyH })
    waitFor { seedClear.historyLoaded }
    copyText("cleared while loading", on: seedClearBoard, into: seedClear)
    seedClear.flushHistory()
    ClipboardHistory.waitForSaves()
    check(savedClips(clearURL, key: keyH)?.count == 1, "the clip to clear is saved")
    let clearGate = DispatchSemaphore(value: 0)
    // The first key read waits for the gate, then the gate is opened again for later reads.
    let clearing = ClipboardHistory(pasteboard: makeBoard(), file: nil, historyFile: clearURL, key: { clearGate.wait(); clearGate.signal(); return keyH })
    check(!clearing.historyLoaded, "the history waits for its key")
    clearing.clear()
    clearGate.signal()
    waitFor { clearing.historyLoaded }
    check(clearing.items.isEmpty, "Clear History during the load keeps the restored clips cleared")
    clearing.flushHistory()
    ClipboardHistory.waitForSaves()
    check((savedClips(clearURL, key: keyH) ?? []).isEmpty, "the saved history is empty after the load")
    clearing.keepsAcrossRestarts = false
    seedClear.keepsAcrossRestarts = false
    ClipboardHistory.waitForSaves()

    // Nothing from these checks stays on: every history is turned off, and the folder is removed.
    for history in [off, first, restarted, locked, damaged, privateHistory] { history.keepsAcrossRestarts = false }
    ClipboardHistory.waitForSaves()
    UserDefaults.standard.removeObject(forKey: "clipboardKeepsAcrossRestarts")
    UserDefaults.standard.removeObject(forKey: "clipboardRestoresLatest")
    try? FileManager.default.removeItem(at: folder)
}

// A recording that was deleted is neither copied nor left as a dead reference.
do {
    let gone = ClipItem(representations: [], digest: "gone", kind: .file, title: "gone.mov", plainText: nil, link: nil, thumbnail: nil,
                        gifURL: nil, fileURLs: [URL(fileURLWithPath: "/nonexistent/library-check-\(UUID().uuidString).mov")], byteCount: 0, date: Date())
    check(ClipboardHistory.refersToMissingFile(gone), "a file item whose file is gone is refused")
    check(!ClipboardHistory.refersToMissingFile(gone, exists: { _ in true }), "a file item whose file exists is copied")
    let board = NSPasteboard(name: NSPasteboard.Name("library-checks-gone-\(UUID().uuidString)"))
    let history = ClipboardHistory(pasteboard: board, file: nil, key: { throw ClipboardKey.KeychainError(status: -1) })
    board.clearContents()
    board.setString("before", forType: .string)
    let changeBefore = board.changeCount
    history.copy(gone)
    check(board.changeCount == changeBefore && board.string(forType: .string) == "before", "copying a missing file leaves the pasteboard alone")
    history.removeFile(at: gone.fileURLs[0])
}

// A screenshot that cannot be read yet is retried, so the read says so; a readable one is converted to PNG.
do {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-shot-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let partial = folder.appendingPathComponent("partial.png")
    try? Data([0x89, 0x50, 0x4E]).write(to: partial)
    if case .unreadable = ScreenCaptures.readPNG(at: partial) {} else { check(false, "a partly written screenshot is unreadable") }
    if case .unreadable = ScreenCaptures.readPNG(at: folder.appendingPathComponent("missing.png")) {} else { check(false, "a missing screenshot is unreadable") }
    let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    let complete = folder.appendingPathComponent("complete.png")
    try? picture?.representation(using: .png, properties: [:])?.write(to: complete)
    if case .png = ScreenCaptures.readPNG(at: complete) {} else { check(false, "a finished screenshot is read as PNG") }
    // A file over the size limit is refused by its size, without reading it. A sparse file costs no disk space.
    let huge = folder.appendingPathComponent("huge.png")
    FileManager.default.createFile(atPath: huge.path, contents: nil)
    if let handle = try? FileHandle(forWritingTo: huge) {
        try? handle.truncate(atOffset: UInt64(ClipboardHistory.maxItemBytes) + 1)
        try? handle.close()
    }
    if case .tooLarge = ScreenCaptures.readPNG(at: huge) {} else { check(false, "a screenshot over the size limit is refused by its size") }
    try? FileManager.default.removeItem(at: folder)
}



// ---- undo in the library store (the real store, in a temporary library folder) ----
let storeHome = FileManager.default.temporaryDirectory.appendingPathComponent("library-store-checks-\(UUID().uuidString)", isDirectory: true)
setenv("LIBRARY_HOME", storeHome.path, 1)
let undoStore = LibraryStore()
let undoLog = UndoManager()
// Every change is grouped by hand, so a whole check runs in one run loop turn and still has one step per action.
undoLog.groupsByEvent = false
undoStore.undoManager = undoLog
/// Runs one user action as its own undo step, the way a menu action or a finished rename does.
@MainActor func step(_ body: () -> Void) {
    undoLog.beginUndoGrouping()
    body()
    undoLog.endUndoGrouping()
}

// A rename whose item is deleted while the field is open does not restore the copy from before the delete.
let renamedA = LibraryItem(name: "A", url: "https://a.example.com")
let renamedB = LibraryItem(name: "B", url: "https://b.example.com")
step { undoStore.nodes = [renamedA, renamedB] }
undoLog.removeAllActions()
step { undoStore.rename(renamedA.id, to: "A2") }
step { undoStore.delete([renamedA.id]) }
step {
    undoStore.rename(renamedB.id, to: "B2")
    undoStore.endRename()
}
undoLog.undo()
check(undoStore.nodes.map(\.name) == ["B"] && undoStore.deleted.map(\.id) == [renamedA.id],
      "a rename after its item was deleted does not undo the delete: \(undoStore.nodes.map(\.name))")

// An edit that changes nothing is not an undo step, so Redo survives it. These run outside any group, as a menu
// action does, so an empty group is not what keeps Redo.
let noopA = LibraryItem(name: "A", url: "https://a.example.com")
let noopB = LibraryItem(name: "B", url: "https://b.example.com")
let noopC = LibraryItem(name: "C", url: "https://c.example.com")
step { undoStore.nodes = [noopA, noopB, noopC] }
undoLog.removeAllActions()
step { undoStore.move([noopB.id], before: noopA.id) }
undoLog.undo()
check(undoLog.canRedo && undoStore.nodes.map(\.name) == ["A", "B", "C"], "the move is undone before the no-op edits")
undoStore.perform("Edit") { _ in }
undoStore.move([noopA.id], before: noopB.id)
undoStore.move([noopB.id], before: noopC.id)
undoStore.rename(noopA.id, to: "A")
undoStore.endRename()
check(undoLog.canRedo, "no-op edits leave Redo alone")
undoLog.redo()
check(undoStore.nodes.map(\.name) == ["B", "A", "C"], "Redo still moves B before A: \(undoStore.nodes.map(\.name))")

// After Undo, Redo is named for the step it redoes, and Undo after Redo is named again.
step { undoStore.move([noopC.id], before: noopA.id) }
step { undoStore.rename(noopA.id, to: "A2"); undoStore.endRename() }
check(undoLog.undoActionName == "Rename", "undo names the last step: \(undoLog.undoActionName)")
undoLog.undo()
check(undoLog.redoActionName == "Rename", "redo is named for the step it redoes: \(undoLog.redoActionName)")
undoLog.undo()
check(undoLog.redoActionName == "Move", "redo after a second undo is named for that step: \(undoLog.redoActionName)")

// Link check results are not edits: undoing a rename keeps the results recorded after the rename.
let linked = LibraryItem(name: "Linked", url: "https://linked.example.com")
let other = LibraryItem(name: "Other", url: "https://other.example.com")
step { undoStore.nodes = [linked, other] }
undoLog.removeAllActions()
step { undoStore.rename(other.id, to: "Other 2"); undoStore.endRename() }
undoStore.recordLinkStatuses([linked.id: LinkStatus(kind: .broken, checked: Date())])
undoLog.undo()
check(undoStore.nodes.map(\.name) == ["Linked", "Other"] && undoStore.nodes.first?.linkStatus?.kind == .broken,
      "undo keeps a link check result recorded after the step: \(undoStore.nodes.first?.linkStatus?.kind as Any)")

// Undo does not bring back Recently Deleted items the 30-day purge has removed, but keeps the ones still within it.
let purgedOld = LibraryItem(name: "Old", url: "https://old.example.com", deletedDate: Date().addingTimeInterval(-31 * 24 * 60 * 60))
let purgedRecent = LibraryItem(name: "Recent", url: "https://recent.example.com", deletedDate: Date().addingTimeInterval(-29 * 24 * 60 * 60))
let purgeSnapshot = LibrarySync.Contents(live: [linked], deleted: [purgedOld, purgedRecent])
check(undoStore.restorable(purgeSnapshot).deleted.map(\.name) == ["Recent"],
      "an undo leaves out the items the purge removed: \(undoStore.restorable(purgeSnapshot).deleted.map(\.name))")
try? FileManager.default.removeItem(at: storeHome)

// A thumbnail is made only from a picture whose header size is reasonable.
check(ClipboardHistory.thumbnailSizeAllowed(width: 5120, height: 2880), "a 5K screenshot gets a thumbnail")
check(!ClipboardHistory.thumbnailSizeAllowed(width: 40_000, height: 40_000), "a picture with a huge header size gets none")
check(!ClipboardHistory.thumbnailSizeAllowed(width: 0, height: 100) && !ClipboardHistory.thumbnailSizeAllowed(width: -1, height: 100), "a picture with no size gets none")

// A bookmark added to a folder that is gone goes to the top level instead of being dropped.
do {
    let folder = LibraryItem(name: "Gone folder", children: [])
    var lib: [LibraryItem] = [folder]
    lib.removeNode(folder.id)
    lib.append(LibraryItem(name: "Lost", url: "a.example.com"), to: folder.id)
    check(lib.map(\.name) == ["Lost"], "a bookmark for a deleted folder lands at the top level")
    var moved: [LibraryItem] = [LibraryItem(name: "Plain", url: "b.example.com")]
    moved.append(LibraryItem(name: "Kept", url: "c.example.com"), to: moved[0].id)
    check(moved.map(\.name) == ["Plain", "Kept"], "a bookmark for a node that is not a folder lands at the top level")
}

// Get Info saves only the fields the user edited. A change made since the sheet opened is kept.
do {
    let base = LibraryItem(name: "Docs", url: "https://docs.example.com", keywords: "old")
    var draft = base
    draft.name = "Documentation"
    var current = base
    current.keywords = "synced"
    current.url = "https://docs.example.com/new"
    current.children = nil
    let merged = current.applying(draft, from: base)
    check(merged.name == "Documentation" && merged.keywords == "synced" && merged.url == "https://docs.example.com/new",
          "an edited field is taken, an unedited field keeps the newer value")
    check(current.applying(base, from: base) == current, "an unchanged editor leaves the item as it is")
}

print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
