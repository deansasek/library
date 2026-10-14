import SwiftUI

/// The page the welcome window shows. An object instead of `@State` because the `@State` macro plugin
/// needs a full Xcode install.
final class WelcomeModel: ObservableObject {
    static let pageCount = 3
    @Published var page: Int
    /// True from the click on Move to Applications until the app quits, so the page can say what is happening.
    @Published var isMoving = false

    init(page: Int = 0) {
        self.page = page
    }
    /// Which way the last page change went, so the new page slides in from the right way.
    private(set) var forward = true

    func go(_ step: Int) {
        forward = step > 0
        page += step
    }
}

/// A first-launch welcome laid out like Apple's own: the app icon, a large bold title, feature rows with tinted
/// symbols, and Back and Continue at the bottom as in Setup Assistant. The second page lets you try each
/// shortcut. The third asks for access and shows whether it was granted.
struct WelcomeView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var model: WelcomeModel
    @ObservedObject private var loginItem = LoginItem.shared
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case 0: intro
                case 1: shortcuts
                default: access
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .id(model.page)
            .transition(model.forward
                ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
            footer
        }
        .frame(width: 540, height: 580)
        .clipped()
        .animation(.easeInOut(duration: 0.28), value: model.page)
    }

    // MARK: Pages

    private var intro: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("Welcome to Library")
                    .font(.largeTitle.bold())
                Text("Everything you open and copy, one shortcut away.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                feature("books.vertical", .blue, "Your Library",
                        "Keep websites, apps, and commands in the menu bar and open any of them in one click.")
                feature("magnifyingglass", .purple, "Quick Open",
                        "Search your library and your clipboard history from anywhere, and do quick math.")
                feature("doc.on.clipboard", .orange, "Clipboard Menu",
                        "Copy as many things as you like. Library remembers them, and you can pin the ones you reuse.")
            }
            Spacer(minLength: 0)
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            header("Your Shortcuts", "These work in every app. Try one now.")
            VStack(spacing: 0) {
                shortcutRow(1, "Quick Open", "magnifyingglass", "Search your library and clipboard.") { store.showQuickOpen() }
                Divider()
                shortcutRow(0, "Library Menu", "contextualmenu.and.cursorarrow", "Your library, at the pointer.") { store.showMenu() }
                Divider()
                shortcutRow(3, "Clipboard Menu", "doc.on.clipboard", "What you copied, at the pointer.") { PopupMenu.showClipboard() }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            Text("Change any of them in Settings, under Shortcuts. Restore Defaults brings these back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
    }

    private var access: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            header("Set Up Library", "A few things help Library work well.")
            VStack(spacing: 0) {
                installRow
                Divider()
                // Re-read every second, so the check mark appears as soon as you allow access in System Settings.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    accessRow
                }
                Divider()
                HStack(spacing: 14) {
                    icon("power.circle", .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at Login").font(.headline)
                        Text("Start Library when you log in, so the shortcuts are always ready.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Open at Login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(14)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            Text("Clipboard history stays in memory and is gone when Library quits. Pinned items are saved on this Mac, and copies from password managers are skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
    }

    /// Whether the app is in the Applications folder, with a button to move it there if it is not.
    private var installRow: some View {
        let installed = Installer.isInApplications
        return HStack(spacing: 14) {
            icon(installed ? "checkmark.circle.fill" : "square.and.arrow.down.on.square", installed ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Applications Folder").font(.headline)
                Text(installText(installed))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Text("Done").foregroundStyle(.secondary)
            } else if model.isMoving {
                ProgressView().controlSize(.small)
            } else {
                Button("Move to Applications") { move() }
            }
        }
        .padding(14)
    }

    private func installText(_ installed: Bool) -> String {
        if installed { return "Library is in your Applications folder." }
        if model.isMoving { return "Moving Library… It will reopen when it’s done." }
        return "Library works best from your Applications folder. It will quit and reopen once."
    }

    /// Shows that the app is about to relaunch, then moves it. The short wait lets that message appear first.
    private func move() {
        model.isMoving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !Installer.moveToApplications() { model.isMoving = false }
        }
    }

    private var accessRow: some View {
        let granted = HotKeys.hasClickAccess
        return HStack(spacing: 14) {
            icon(granted ? "checkmark.circle.fill" : "hand.raised.circle", granted ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility").font(.headline)
                Text("Lets Library see Control and right click, scrolls, and gestures, and read a link you select so it can suggest adding it. Everything else works without it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button("Allow…") { HotKeys.requestClickAccess() }
            }
        }
        .padding(14)
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            if model.page > 0 {
                Button("Back") { model.go(-1) }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button(model.page == WelcomeModel.pageCount - 1 ? "Get Started" : "Continue") {
                if model.page == WelcomeModel.pageCount - 1 { close() } else { model.go(1) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .padding(.top, 8)
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.title)
            .imageScale(.large)
            .foregroundStyle(color)
            .frame(width: 36)
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            icon(symbol, color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(_ index: Int, _ title: String, _ symbol: String, _ detail: String,
                             tryIt: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            icon(symbol, .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if store.failedExtras.contains(index) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Another app uses this shortcut. Choose another in Settings.")
            }
            Text(store.extraHotkeys[index]?.description ?? "Not set")
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button("Try", action: tryIt)
                .buttonStyle(.link)
        }
        .padding(14)
    }
}
