import AppKit
import SwiftUI

// Renders the app's views to PNG files, in light and dark appearance. Each view is drawn in an off-screen window,
// so no Screen Recording or Accessibility permission and no Xcode is needed. Run it with Tests/render.sh.
//
// The library store reads and writes ~/.library, and the clipboard history keeps clipboard.json there, so the
// harness points LIBRARY_HOME at a temporary folder first. Your library and clipboard history are not touched.

/// Where the PNGs go.
var outputFolder = URL(fileURLWithPath: ".")
var written = 0
var problems: [String] = []

/// Renders `view` at `width` x `height` (or fitted to its content when `height` is nil) on a window-colored
/// background, and writes `<name>-light.png` or `<name>-dark.png`.
@MainActor
func save<V: View>(_ name: String, width: CGFloat, height: CGFloat? = nil, backdrop: AnyShapeStyle? = nil,
                   dark: Bool, prepare: (() -> Void)? = nil, _ view: V) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    appearance.performAsCurrentDrawingAppearance {
        let framed: AnyView = height.map { AnyView(view.frame(width: width, height: $0)) }
            ?? AnyView(view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        let content = framed
            .background(backdrop ?? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
            .environment(\.colorScheme, dark ? .dark : .light)
        // The view is hosted in an off-screen window and drawn into a bitmap. ImageRenderer would be simpler,
        // but it cannot draw AppKit-backed controls (text fields, lists), so they come out as placeholders.
        let host = NSHostingView(rootView: content)
        host.appearance = appearance
        let size = height.map { NSSize(width: width, height: $0) } ?? NSSize(width: width, height: host.fittingSize.height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        // Let SwiftUI lay out, run its appear actions, and finish its first animation frames.
        settle(for: 0.3)
        // Some views reset their state when they appear, so a state set for the picture goes in after that.
        if let prepare {
            prepare()
            settle(for: 0.2)
        }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            problems.append("\(name): no bitmap")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.close()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            problems.append("\(name): could not encode")
            return
        }
        let file = outputFolder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        do {
            try png.write(to: file)
            written += 1
        } catch {
            problems.append("\(name): \(error.localizedDescription)")
        }
    }
}

/// Runs the main run loop for `seconds`, so SwiftUI and AppKit can lay out and draw, and Tasks can run.
@MainActor
func settle(for seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Lets the main run loop run until `condition` holds, so the Tasks that compute Quick Open results can finish.
@MainActor
func settle(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(0.5)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
func sampleTree() -> [LibraryItem] {
    let jira = LibraryItem(name: "Jira", url: "https://tickets.example.com/browse/{}")
    var safari = LibraryItem(name: "Safari", appPath: "/System/Applications/Safari.app")
    safari.shortcuts = [Shortcut(modifiers: 0)]
    var github = LibraryItem(name: "GitHub", url: "https://github.com")
    github.color = "blue"
    github.keywords = "code git"
    var notes = LibraryItem(name: "Build the release", command: "make release")
    notes.color = "orange"
    return [
        LibraryItem(name: "Apps", isDivider: true),
        safari,
        github,
        LibraryItem(name: "Work", children: [
            jira,
            LibraryItem(name: "Calendar", url: "https://calendar.example.com"),
            LibraryItem(name: "Reading", children: [
                LibraryItem(name: "Docs with a very long name that has to be truncated in the row", url: "https://docs.example.com/a/very/long/path/that/keeps/going"),
            ]),
        ]),
        notes,
    ]
}

@MainActor
func run() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    let args = CommandLine.arguments
    guard args.count == 2 else {
        print("usage: render <output folder>")
        exit(2)
    }
    outputFolder = URL(fileURLWithPath: args[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

    let home = FileManager.default.temporaryDirectory.appendingPathComponent("library-render-\(UUID().uuidString)")
    setenv("LIBRARY_HOME", home.path, 1)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    guard LibraryStore.dir.path.hasPrefix(home.path) else {
        print("LIBRARY_HOME is not honored, so the harness would touch the real library. Stopping.")
        try? FileManager.default.removeItem(at: home)
        exit(1)
    }

    let store = LibraryStore.shared
    store.nodes = sampleTree()

    // Quick Open, empty query: the browse list.
    let browse = QuickOpenModel(store: store, selectedText: nil, pastes: false)
    browse.appeared = true
    browse.resetSelection()

    // Quick Open with results for "git".
    let results = QuickOpenModel(store: store, selectedText: nil, pastes: false)
    results.appeared = true
    results.query = "git"
    settle { !results.results.isEmpty }
    results.selection = results.results.first?.id

    // Quick Open with the action list (Tab).
    let actions = QuickOpenModel(store: store, selectedText: nil, pastes: false)
    actions.appeared = true
    actions.query = "git"
    settle { !actions.results.isEmpty }
    actions.selection = actions.results.first?.id

    // Quick Open with a query that matches nothing: only the web search suggestion is left.
    let none = QuickOpenModel(store: store, selectedText: nil, pastes: false)
    none.appeared = true
    none.query = "zzqxv"
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    let backdrop = AnyShapeStyle(LinearGradient(colors: [.teal, .indigo, .pink],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
    for dark in [false, true] {
        save("quickopen-browse", width: 780, height: 520, backdrop: backdrop, dark: dark,
             QuickOpenView(model: browse) {})
        save("quickopen-results", width: 780, height: 520, backdrop: backdrop, dark: dark,
             QuickOpenView(model: results) {})
        save("quickopen-actions", width: 780, height: 520, backdrop: backdrop, dark: dark,
             prepare: { actions.showActions = true }, QuickOpenView(model: actions) {})
        save("quickopen-no-results", width: 780, height: 520, backdrop: backdrop, dark: dark,
             QuickOpenView(model: none) {})
    }

    for dark in [false, true] {
        for page in 0..<WelcomeModel.pageCount {
            save("welcome-\(page + 1)", width: 540, height: 580, dark: dark,
                 WelcomeView(store: store, model: WelcomeModel(page: page)) {})
        }
        save("settings-general", width: 500, dark: dark, SettingsView(store: store).general)
        save("settings-shortcuts", width: 500, dark: dark, SettingsView(store: store).shortcuts)
        save("settings-clipboard", width: 500, dark: dark, SettingsView(store: store).clipboard)
        save("manager", width: 780, height: 420, dark: dark, ManageView(store: store))
    }

    // Sheets. Bookmark import is an open panel and an alert, not a sheet, so it has nothing to render here.
    let state = ManageState()
    state.sheet = .bookmark
    state.name = "Example"
    state.url = "https://example.com"
    state.folderID = nil
    let empty = ManageState()
    empty.sheet = .application
    empty.apps = InstalledApp.scan()
    empty.appSelection = empty.apps.first?.id
    let edit = ManageState()
    let editing = sampleTree()[2]
    edit.sheet = .edit(editing.id)
    edit.draft = editing
    for dark in [false, true] {
        save("sheet-add-bookmark", width: 400, dark: dark, AddSheet(store: store, state: state) {})
        save("sheet-application", width: 420, height: 480, dark: dark, AppPickerSheet(store: store, state: empty) {})
        save("sheet-edit", width: 440, dark: dark, EditSheet(store: store, state: edit) {})
    }

    // The empty manager window shows ContentUnavailableView, so it needs an empty library.
    store.nodes = []
    for dark in [false, true] {
        save("manager-empty", width: 780, height: 420, dark: dark, ManageView(store: store))
    }

    try? FileManager.default.removeItem(at: home)
    print("Wrote \(written) PNGs to \(outputFolder.path)")
    for problem in problems {
        print("PROBLEM: \(problem)")
    }
    exit(problems.isEmpty ? 0 : 1)
}

MainActor.assumeIsolated { run() }
