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

    // Quick Open with a query that matches nothing.
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
        // The same results on the window background, so the contrast check below samples text on a plain color.
        save("contrast-quickopen-results", width: 780, height: 520, dark: dark, QuickOpenView(model: results) {})
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

    checkContrast()

    try? FileManager.default.removeItem(at: home)
    print("Wrote \(written) PNGs to \(outputFolder.path)")
    for problem in problems {
        print("PROBLEM: \(problem)")
    }
    exit(problems.isEmpty ? 0 : 1)
}

// MARK: Contrast of text in the rendered PNGs

/// A color as 0...255 sRGB components.
typealias RGB = (r: Int, g: Int, b: Int)

/// WCAG 2.x relative luminance.
func luminance(_ color: RGB) -> Double {
    func linear(_ value: Int) -> Double {
        let c = Double(value) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

/// WCAG contrast ratio, from 1 to 21.
func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

func hex(_ color: RGB) -> String {
    String(format: "#%02x%02x%02x", color.r, color.g, color.b)
}

/// One line of text to measure. `rect` is in points from the top left of the PNG, which is `width` points wide.
/// `semantic` is the system color the view asks for, resolved over `background` for the design value. `lightSemantic`
/// replaces it in light mode when the view uses a different color there. Text on a selection color is measured from
/// the rendered pixels, because the selection color is translucent over the panel.
struct TextSample {
    let screen: String
    let label: String
    let rect: CGRect
    let width: CGFloat
    let semantic: NSColor
    let background: NSColor
    var lightSemantic: NSColor? = nil
    /// Set when this text cannot be read in the off-screen render, with the reason. It is printed, not measured.
    var skip: String? = nil
}

/// The color a semantic color has on a background, in the given appearance, as 0...255 sRGB.
@MainActor
func resolved(_ color: NSColor, over background: NSColor, appearance: NSAppearance) -> RGB {
    var result: RGB = (0, 0, 0)
    appearance.performAsCurrentDrawingAppearance {
        let bg = background.usingColorSpace(.sRGB)!
        let fg = color.usingColorSpace(.sRGB)!
        let a = Double(fg.alphaComponent)
        func mix(_ f: CGFloat, _ b: CGFloat) -> Int { Int((Double(f) * 255 * a + Double(b) * 255 * (1 - a)).rounded()) }
        result = (mix(fg.redComponent, bg.redComponent), mix(fg.greenComponent, bg.greenComponent),
                  mix(fg.blueComponent, bg.blueComponent))
    }
    return result
}

/// The pixel view of a line of text: the most common color in the rectangle is the background, and the pixel that
/// contrasts most with it is the text. Anti-aliasing only pulls text pixels toward the background, so this ratio can
/// be lower than the real one but not higher.
@MainActor
func sampledPixels(_ file: URL, _ sample: TextSample) -> (text: RGB, background: RGB)? {
    guard let data = try? Data(contentsOf: file), let rep = NSBitmapImageRep(data: data) else { return nil }
    let scale = CGFloat(rep.pixelsWide) / sample.width
    var pixels: [RGB] = []
    var counts: [String: Int] = [:]
    for y in Int(sample.rect.minY * scale)..<Int(sample.rect.maxY * scale) {
        for x in Int(sample.rect.minX * scale)..<Int(sample.rect.maxX * scale) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let rgb = (r: Int((color.redComponent * 255).rounded()), g: Int((color.greenComponent * 255).rounded()),
                       b: Int((color.blueComponent * 255).rounded()))
            pixels.append(rgb)
            counts["\(rgb.r),\(rgb.g),\(rgb.b)", default: 0] += 1
        }
    }
    guard let (key, _) = counts.max(by: { $0.value < $1.value }) else { return nil }
    let parts = key.split(separator: ",").map { Int($0)! }
    let background: RGB = (parts[0], parts[1], parts[2])
    guard let text = pixels.max(by: { contrastRatio($0, background) < contrastRatio($1, background) }) else { return nil }
    return (text, background)
}

/// The Quick Open rows and the Settings labels, in light and dark. The design color is the semantic color the view
/// asks for, resolved in each appearance over the background it is drawn on. The rendered pixels confirm the color
/// reached the PNG. Failures are reported with both values.
@MainActor
func checkContrast() {
    let qo = "contrast-quickopen-results"
    // Quick Open sits on glassEffect. Off screen, that glass draws the primary text black in dark mode and the
    // secondary text black in light mode, so only light-mode primary text there can be read in this render.
    let glassNote = "Quick Open sits on glassEffect, which renders its text in another color off screen, so this cannot be read here"
    let samples: [TextSample] = [
        TextSample(screen: qo, label: "selected row title", rect: CGRect(x: 70, y: 126, width: 110, height: 18), width: 780,
                   semantic: .alternateSelectedControlTextColor, background: .selectedContentBackgroundColor,
                   lightSemantic: .labelColor),
        TextSample(screen: qo, label: "selected row detail", rect: CGRect(x: 70, y: 143, width: 100, height: 16), width: 780,
                   semantic: .alternateSelectedControlTextColor, background: .selectedContentBackgroundColor,
                   lightSemantic: .labelColor),
        TextSample(screen: qo, label: "row title", rect: CGRect(x: 72, y: 196, width: 330, height: 18), width: 780,
                   semantic: .labelColor, background: .windowBackgroundColor),
        TextSample(screen: qo, label: "row detail", rect: CGRect(x: 72, y: 215, width: 330, height: 14), width: 780,
                   semantic: .secondaryLabelColor, background: .windowBackgroundColor, skip: glassNote),
        TextSample(screen: "settings-general", label: "Open at login", rect: CGRect(x: 30, y: 32, width: 80, height: 16), width: 500,
                   semantic: .labelColor, background: .windowBackgroundColor),
        TextSample(screen: "settings-general", label: "Welcome Screen", rect: CGRect(x: 30, y: 121, width: 95, height: 16), width: 500,
                   semantic: .labelColor, background: .windowBackgroundColor),
        TextSample(screen: "settings-general", label: "Version", rect: CGRect(x: 30, y: 162, width: 55, height: 16), width: 500,
                   semantic: .labelColor, background: .windowBackgroundColor),
        TextSample(screen: "settings-general", label: "footer detail", rect: CGRect(x: 30, y: 66, width: 330, height: 16), width: 500,
                   semantic: .secondaryLabelColor, background: .windowBackgroundColor, lightSemantic: .labelColor),
    ]
    for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        for sample in samples {
            let name = "\(sample.screen) \(sample.label) (\(mode))"
            if let reason = sample.skip ?? (dark && sample.screen == qo && sample.label == "row title" ? glassNote : nil) {
                print("contrast skipped: \(name). \(reason).")
                continue
            }
            let file = outputFolder.appendingPathComponent("\(sample.screen)-\(mode).png")
            guard let pixels = sampledPixels(file, sample) else {
                problems.append("contrast: could not read \(name)")
                continue
            }
            let bg = resolved(sample.background, over: .clear, appearance: appearance)
            let semantic = (!dark ? sample.lightSemantic : nil) ?? sample.semantic
            let design = resolved(semantic, over: sample.background, appearance: appearance)
            let designRatio = contrastRatio(design, bg)
            let pixelRatio = contrastRatio(pixels.text, pixels.background)
            let detail = String(format: "design %.2f:1 (%@ on %@), rendered %.2f:1 (%@ on %@)", designRatio,
                                hex(design), hex(bg), pixelRatio, hex(pixels.text), hex(pixels.background))
            // Selection colors are translucent over the panel, so their rendered pixels are the value that counts.
            let measured = sample.background == .selectedContentBackgroundColor ? pixelRatio : designRatio
            if measured < 4.5 {
                problems.append("contrast below 4.5:1 for \(name): \(detail)")
            } else {
                print("contrast \(detail) \(name)")
            }
        }
    }
}

MainActor.assumeIsolated { run() }
