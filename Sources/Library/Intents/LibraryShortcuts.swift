import AppIntents

/// The actions Shortcuts and Spotlight offer by name. Each phrase names Library, so the phrases stay unambiguous.
struct LibraryShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookmarkIntent(),
            phrases: ["Open \(\.$item) in \(.applicationName)"],
            shortTitle: "Open Item",
            systemImageName: "bookmark"
        )
        AppShortcut(
            intent: ShowQuickOpenIntent(),
            phrases: ["Search \(.applicationName)"],
            shortTitle: "Quick Open",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenClipboardLinkIntent(),
            phrases: ["Open clipboard link in \(.applicationName)"],
            shortTitle: "Open Clipboard Link",
            systemImageName: "link"
        )
        AppShortcut(
            intent: FrequentlyUsedIntent(),
            phrases: ["Show frequently used in \(.applicationName)"],
            shortTitle: "Frequently Used",
            systemImageName: "star"
        )
        AppShortcut(
            intent: ShowMenuIntent(),
            phrases: ["Show \(.applicationName) menu"],
            shortTitle: "Show Menu",
            systemImageName: "menubar.rectangle"
        )
    }
}
