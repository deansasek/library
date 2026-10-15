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
    @ObservedObject private var screenCaptures = ScreenCaptures.shared
    @ObservedObject private var tracking = TrackingPreferences.shared
    @ObservedObject private var clipLock = ClipboardLock.shared
    @StateObject private var recording = RecordingState()
    @AppStorage(UpdateCheck.automaticKey) private var checksForUpdates = true
    @AppStorage(LinkChecker.enabledKey) private var checksLinks = false
    @AppStorage(SmartTitle.key) private var namesFromPages = false
    @AppStorage("confirmTerminalCommands") private var confirmTerminalCommands = false

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
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
            } footer: {
                Text("Library lives in the menu bar and opens its items from there.")
            }
            Section {
                Toggle(isOn: $namesFromPages) {
                    Text("Name new bookmarks from their pages", bundle: L10n.bundle)
                }
            } footer: {
                Text("Library requests each new bookmark’s page once to read its title. Until the title arrives, or when the page has none, the bookmark is named after its host.", bundle: L10n.bundle)
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
                    Text("Check for updates automatically", bundle: L10n.bundle)
                }
                .onChange(of: checksForUpdates) { _, _ in UpdateCheck.startAutomaticChecks() }
            } footer: {
                Text("Library checks GitHub for a newer version every hour while it runs. When one is available, it appears at the top of the Library menu. Check for Updates… in the menu checks now.")
            }
            Section {
                Toggle(isOn: $checksLinks) {
                    Text("Check links periodically", bundle: L10n.bundle)
                }
                .onChange(of: checksLinks) { _, _ in LinkChecker.startSchedule(store: store) }
            } footer: {
                Text("Once a day while Library is open, Library quickly checks that each bookmark’s page is still there. It doesn’t download the page. If a site doesn’t answer that quick check, Library loads the page and reads only its first 64 KB. Each bookmark is checked at most once a day. Bookmarks whose page is missing or can’t be reached show a warning in Edit Library. Off by default. Choose Check Links in the File menu to check now.", bundle: L10n.bundle)
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
                Text("Export saves your bookmarks, folders, shortcuts, icons, keywords, colors, templates, and Open at login settings to a file. Restore replaces your library with a backup and can be undone. Clipboard items are not included, because pinned clipboard items are encrypted with a key that stays on this Mac.")
            }
            Section {
                Toggle(isOn: $confirmTerminalCommands) {
                    Text("Confirm terminal commands", bundle: L10n.bundle)
                }
            } footer: {
                Text("Asks before a terminal command runs, whether it starts from a shortcut, Spotlight, a menu, or Open at Login. The confirmation shows the command, and Cancel is the default.", bundle: L10n.bundle)
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
                Picker("Library menu opens", selection: $store.menuMode) {
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
                Toggle("Keep clipboard history", isOn: $history.isEnabled)
                Toggle("Paste into text fields", isOn: $history.pastesIntoFields)
                Toggle("Play copied GIFs", isOn: $history.playsGIFs)
                Toggle("Add screenshots and recordings", isOn: $screenCaptures.isEnabled)
                Toggle("Remove tracking parameters when copying links", isOn: $tracking.removesOnCopy)
                Button("Clear History") { history.clear() }
                    .disabled(history.items.allSatisfy(\.pinned))
            } footer: {
                Text("History stays in memory and is gone when Library quits, unless Keep clipboard history across restarts is on. With Paste into text fields on, choosing an item while a text field has the keyboard pastes it, and otherwise copies it. That needs Accessibility access. Browsers copy a still picture of a GIF. Turn on Play Copied GIFs to download the original GIF from the page so it can play. It is off by default. Pinned items are the exception: they are saved on this Mac in clipboard.json, so text you keep survives a restart. Copies that password managers mark as private are skipped, and so are copies made in password manager apps. Add screenshots and recordings adds each new screenshot to history as an image, and each recording as a link to its file. Remove tracking parameters removes tracking codes such as utm_source, fbclid, and gclid from a link you copy back from the history. The rest of the link stays the same, and the saved link is not changed. It only adds captures made after you turn it on. Library finds them with Spotlight and does not watch a folder.")
            }
            Section {
                Toggle(isOn: $history.keepsAcrossRestarts) {
                    Text("Keep clipboard history across restarts", bundle: L10n.bundle)
                }
            } footer: {
                Text("Saves your unpinned clipboard history, encrypted with a key kept in your Keychain, so it is there after you restart. Pinned items are saved either way. Copies from password managers and copies marked private are never saved. Images over 5 MB are never saved, to keep the file small. Turning this off deletes the saved history.", bundle: L10n.bundle)
            }
            Section {
                Toggle(isOn: $history.restoresLatestAtLaunch) {
                    Text("Put the Latest Item on the Clipboard When Library Opens", bundle: L10n.bundle)
                }
                .disabled(!history.keepsAcrossRestarts)
            } footer: {
                Text("The newest saved item is copied to the clipboard when Library opens, so you can paste it right away. A password copied before a restart could be pasted by someone else at this Mac.", bundle: L10n.bundle)
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
