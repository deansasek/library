import AppKit
import CryptoKit
import Carbon

var failures = 0
@MainActor func check(_ ok: Bool, _ what: String, line: Int = #line) { if !ok { failures += 1; print("FAIL line \(line): \(what)") } }
func answer(_ q: String) -> String? { QuickAnswers.answer(for: q)?.value }

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

// ---- suggestions ----
let sel = AddSuggestion.make(selection: "https://swift.org/docs", clipboard: nil, in: tree())
check(sel?.source == .selection && sel?.node.name == "swift.org", "a selected link is suggested")
check(AddSuggestion.make(selection: "just some words", clipboard: nil, in: tree()) == nil, "plain selected text is not")
check(AddSuggestion.make(selection: "https://docs.example.com", clipboard: nil, in: tree()) == nil, "a link already in the library is not")
check(AddSuggestion.make(selection: nil, clipboard: nil, in: tree()) == nil, "nothing to suggest")

// ---- quick answers ----
check(answer("12*8") == "96" && answer("(2+3)*4") == "20" && answer("2^10") == "1024" && answer("10/4") == "2.5", "arithmetic")
check(answer("5/0") == nil && answer("42") == nil && answer("2+") == nil && answer("jira") == nil, "not answers")
check(answer("5 km in miles")?.hasPrefix("3.10685") == true && answer("72 f to c")?.hasPrefix("22.2222") == true, "conversions")
check(answer("5 km in kg") == nil, "mismatched units")

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
    let board = NSPasteboard(name: NSPasteboard.Name("library-checks-\(UUID().uuidString)"))
    let saveFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-\(UUID().uuidString).json")
    let history = ClipboardHistory(pasteboard: board, file: saveFile, key: { testKey })

    // A plain-text pinned file from before encryption is migrated on load, leaving no plain text behind.
    let legacyFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-legacy-\(UUID().uuidString).json")
    let legacy = [PinnedFile.Clip(source: "Notes", date: Date(), representations: [["public.utf8-plain-text": Data("legacy pin".utf8)]])]
    try? JSONEncoder().encode(legacy).write(to: legacyFile)
    let migrated = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-m-\(UUID().uuidString)")), file: legacyFile, key: { testKey })
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
    check(damagedHistory.items.isEmpty && !FileManager.default.fileExists(atPath: damagedFile.path) && FileManager.default.fileExists(atPath: movedAside.path), "a damaged file is kept aside")
    try? FileManager.default.removeItem(at: movedAside)

    // With no key, a sealed file is neither moved nor overwritten.
    let lockedFile = FileManager.default.temporaryDirectory.appendingPathComponent("library-checks-locked-\(UUID().uuidString).json")
    let sealedBytes = (try? PinnedFile.encode(legacy, key: testKey)) ?? Data()
    try? sealedBytes.write(to: lockedFile)
    let locked = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-l-\(UUID().uuidString)")), file: lockedFile, key: { throw ClipboardKey.KeychainError(status: -1) })
    check(locked.items.isEmpty && (try? Data(contentsOf: lockedFile)) == sealedBytes, "no key leaves the sealed file untouched")
    try? FileManager.default.removeItem(at: lockedFile)

    // Copies are built in the background, so a check waits until the history has added them.
    @MainActor func settle() {
        let deadline = Date().addingTimeInterval(5)
        while history.pendingCaptures > 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

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
    check(FileManager.default.fileExists(atPath: saveFile.path), "pinning saves the file")
    check(((try? FileManager.default.attributesOfItem(atPath: saveFile.path))?[.posixPermissions] as? Int) == 0o600, "private file")
    let pinnedBytes = (try? Data(contentsOf: saveFile)) ?? Data()
    check((try? JSONDecoder().decode([PinnedFile.Clip].self, from: pinnedBytes)) == nil, "the pinned file is not plain JSON")
    if let pinnedText = history.items.first(where: \.pinned)?.plainText {
        check(pinnedBytes.range(of: Data(pinnedText.utf8)) == nil, "the pinned file hides the pinned text")
    } else { check(false, "an item is pinned") }
    let reloaded = ClipboardHistory(pasteboard: NSPasteboard(name: NSPasteboard.Name("library-checks-2-\(UUID().uuidString)")), file: saveFile, key: { testKey })
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

print(failures == 0 ? "ALL CHECKS PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
