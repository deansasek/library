import SwiftUI

/// Which shortcut field is recording. An object instead of `@State` because
/// the `@State` macro plugin needs a full Xcode install.
final class RecordingState: ObservableObject {
    @Published var target: Int?
}

/// Settings in tabs, as System Settings and most Mac apps do it. The window resizes to each tab.
struct SettingsView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject private var loginItem = LoginItem.shared
    @ObservedObject private var history = ClipboardHistory.shared
    @StateObject private var recording = RecordingState()

    var body: some View {
        TabView {
            general.navigationTitle("General").tabItem { Label("General", systemImage: "gearshape") }
            shortcuts.navigationTitle("Shortcuts").tabItem { Label("Shortcuts", systemImage: "keyboard") }
            clipboard.navigationTitle("Clipboard").tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
        }
        .frame(width: 500)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
            } footer: {
                Text("Library lives in the menu bar and opens its items from there.")
            }
            Section {
                LabeledContent("Welcome Screen") {
                    Button("Show…") { Welcome.show(store: store) }
                }
                LabeledContent("Version", value: version)
            } footer: {
                Text("The welcome screen explains Library, lists your shortcuts, and asks for access. The build number changes with every build, so you can tell which one is running after an update.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    private var shortcuts: some View {
        Form {
            Section {
                LabeledContent("Shortcut") { field(0, $store.extraHotkeys[0]) }
                Picker("Show menu", selection: $store.menuMode) {
                    Text("At mouse pointer").tag(MenuMode.cursor)
                    Text("In menu bar").tag(MenuMode.menuBar)
                }
            } header: {
                Text("Library Menu")
            } footer: {
                Text("Opens your library from any app.")
            }
            Section {
                LabeledContent("Shortcut") { field(1, $store.extraHotkeys[1]) }
            } header: {
                Text("Quick Open")
            } footer: {
                Text("A search field over everything in your library and your clipboard history. Press Return to open the top result.")
            }
            Section {
                LabeledContent("Open Link") { field(2, $store.extraHotkeys[2]) }
                LabeledContent("Clipboard Menu") { field(3, $store.extraHotkeys[3]) }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Open Link opens the web link you last copied. A beep means the clipboard has no link. The menu shows what you copied, at the pointer. To add a copied link to your library, choose Add to Library in Quick Open.")
            }
            if store.clickAccessMissing {
                Section {
                    LabeledContent("Clicks, scrolls, and gestures") {
                        Button("Grant Access…") { HotKeys.requestClickAccess() }
                    }
                } footer: {
                    Text("macOS needs Accessibility access to intercept clicks, scrolls, pinches, and swipes.")
                }
            }
            Section {
                Button("Restore Defaults") { store.restoreDefaultHotkeys() }
            } footer: {
                Text("Control and right click opens the Library menu. Control-Space opens Quick Open. Control-Command-V opens the clipboard history menu. macOS may use Control-Space to switch input sources.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var clipboard: some View {
        Form {
            Section {
                Toggle("Keep Clipboard History", isOn: $history.isEnabled)
                Toggle("Play Copied GIFs", isOn: $history.playsGIFs)
                Button("Clear History") { history.clear() }
                    .disabled(history.items.allSatisfy(\.pinned))
            } footer: {
                Text("History stays in memory and is gone when Library quits. Browsers copy a still picture of a GIF, so Library downloads the original GIF from the page to play it. Turn off Play Copied GIFs to skip those downloads. Pinned items are the exception: they are saved on this Mac in clipboard.json, so text you keep survives a restart. Copies that password managers mark as private are skipped, and so are copies made in password manager apps.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ index: Int, _ shortcut: Binding<Shortcut?>) -> some View {
        HStack {
            if store.failedExtras.contains(index) {
                Image(systemName: "exclamationmark.triangle")
                    .help("In use by another app")
            }
            ShortcutField(shortcut: shortcut,
                          isRecording: recording.target == index,
                          setRecording: { recording.target = $0 ? index : nil })
        }
    }
}
