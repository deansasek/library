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
    @ObservedObject private var tracking = TrackingPreferences.shared
    @ObservedObject private var clipLock = ClipboardLock.shared
    @StateObject private var recording = RecordingState()
    @AppStorage(UpdateCheck.automaticKey) private var checksForUpdates = true
    @AppStorage(LinkChecker.enabledKey) private var checksLinks = false

    var body: some View {
        TabView {
            general.navigationTitle(String(localized: "General", bundle: L10n.bundle)).tabItem {
                Label { Text("General", bundle: L10n.bundle) } icon: { Image(systemName: "gearshape") }
            }
            shortcuts.navigationTitle(String(localized: "Shortcuts", bundle: L10n.bundle)).tabItem {
                Label { Text("Shortcuts", bundle: L10n.bundle) } icon: { Image(systemName: "keyboard") }
            }
            clipboard.navigationTitle(String(localized: "Clipboard", bundle: L10n.bundle)).tabItem {
                Label { Text("Clipboard", bundle: L10n.bundle) } icon: { Image(systemName: "doc.on.clipboard") }
            }
        }
        .frame(width: 500)
    }

    var general: some View {
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
                Toggle("Keep Library in iCloud Drive", isOn: Binding(
                    get: { store.keepsInICloud },
                    set: { store.setKeepsInICloud($0) }
                ))
            } header: {
                Text("Storage")
            } footer: {
                Text("Library keeps bookmarks.json in iCloud Drive, so your library follows you to your other Macs. Clipboard history stays on this Mac.")
            }
            Section {
                Toggle(isOn: $checksForUpdates) {
                    Text("Check for Updates Automatically", bundle: L10n.bundle)
                }
                .onChange(of: checksForUpdates) { _, _ in UpdateCheck.startAutomaticChecks() }
            } footer: {
                Text("Library checks GitHub for a newer version every hour while it runs. When one is available, it appears at the top of the Library menu. Check for Updates… in the menu checks now.")
            }
            Section {
                Toggle(isOn: $checksLinks) {
                    Text("Check Links Periodically", bundle: L10n.bundle)
                }
                .onChange(of: checksLinks) { _, _ in LinkChecker.startSchedule(store: store) }
            } footer: {
                Text("Once a day while Library runs, Library requests each bookmark’s address with a HEAD request, which reads no page content. Each address is requested once per check, and one checked in the last 24 hours is skipped. Bookmarks whose page fails or can’t be reached get a warning in Edit Library. Off by default. Check Links in the File menu checks now.", bundle: L10n.bundle)
            }
            Section {
                LabeledContent("Library") {
                    HStack {
                        Button("Export…") { LibraryBackupActions.export(store) }
                        Button("Restore…") { LibraryBackupActions.restore(store) }
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export saves your bookmarks, folders, shortcuts, icons, keywords, colors, templates, and Open at Login settings to a file. Restore replaces your library with a backup and can be undone. Clipboard items are not included, because pinned clipboard items are encrypted with a key that stays on this Mac.")
            }
            Section {
                LabeledContent("Welcome Screen") {
                    Button("Show…") { Welcome.show(store: store) }
                }
                LabeledContent("Version", value: version)
            } footer: {
                Text("The welcome screen explains Library, lists your shortcuts, and asks for access. The build number changes with every build, so you can tell which one is running after an update.")
            }
            Section {
                Toggle("Remove tracking parameters when copying links", isOn: $tracking.removesOnCopy)
            } footer: {
                Text("Removes tracking codes such as utm_source, fbclid, and gclid from a link you copy. The other parts of the link stay the same, and the saved link is not changed.")
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

    /// One list of actions, each named with a verb, as Keyboard Shortcuts in System Settings lists them.
    var shortcuts: some View {
        Form {
            Section {
                LabeledContent("Show Library Menu") { field(0, $store.extraHotkeys[0]) }
                LabeledContent("Show Quick Open") { field(1, $store.extraHotkeys[1]) }
                LabeledContent("Show Clipboard Menu") { field(3, $store.extraHotkeys[3]) }
                LabeledContent("Open Copied Link") { field(2, $store.extraHotkeys[2]) }
            } footer: {
                Text("These work in every app. Quick Open searches your library and your clipboard history. Open Copied Link opens the web link you last copied. A beep means the clipboard has no link.")
            }
            Section {
                Picker("Library Menu Opens", selection: $store.menuMode) {
                    Text("At the Pointer").tag(MenuMode.cursor)
                    Text("From the Menu Bar").tag(MenuMode.menuBar)
                }
            }
            if store.clickAccessMissing {
                Section {
                    LabeledContent("Accessibility") {
                        Button("Allow…") { HotKeys.requestClickAccess() }
                    }
                } footer: {
                    Text("Clicks, scrolls, pinches, and swipes need Accessibility access. So does suggesting a link you selected.")
                }
            }
            Section {
                Button("Restore Defaults") { store.restoreDefaultHotkeys() }
            } footer: {
                Text("The defaults are Control and right click for the Library menu, Control-Space for Quick Open, and Control-Command-V for the clipboard menu. macOS may use Control-Space to switch input sources.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    var clipboard: some View {
        Form {
            Section {
                Toggle("Require Touch ID or password to show pinned items", isOn: Binding(
                    get: { clipLock.isRequired },
                    set: { clipLock.setRequired($0) }
                ))
            } footer: {
                Text("Pinned items show as Pinned Item until you authenticate with Touch ID or your Mac password. They stay unlocked until you choose Lock Pinned Items in the Library menu, the Mac sleeps, or Library quits.")
            }
            Section {
                Toggle("Keep Clipboard History", isOn: $history.isEnabled)
                Toggle("Paste Into Text Fields", isOn: $history.pastesIntoFields)
                Toggle("Play Copied GIFs", isOn: $history.playsGIFs)
                Button("Clear History") { history.clear() }
                    .disabled(history.items.allSatisfy(\.pinned))
            } footer: {
                Text("History stays in memory and is gone when Library quits. With Paste Into Text Fields on, choosing an item while a text field has the keyboard pastes it, and otherwise copies it. That needs Accessibility access. Browsers copy a still picture of a GIF. Turn on Play Copied GIFs to download the original GIF from the page so it can play. It is off by default. Pinned items are the exception: they are saved on this Mac in clipboard.json, so text you keep survives a restart. Copies that password managers mark as private are skipped, and so are copies made in password manager apps.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ index: Int, _ shortcut: Binding<Shortcut?>) -> some View {
        HStack {
            if store.failedExtras.contains(index) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("In use by another app")
                    .accessibilityLabel("In use by another app")
            }
            ShortcutField(shortcut: shortcut,
                          isRecording: recording.target == index,
                          setRecording: { recording.target = $0 ? index : nil })
        }
    }
}
