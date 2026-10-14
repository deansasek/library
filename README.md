<div align="center">

<img src="docs/AppIcon.png" width="128" height="128" alt="Library app icon">

# Library

Everything you open and copy, one shortcut away.

</div>

Library is a menu bar app for macOS. It keeps your bookmarks, applications, folders, and terminal commands in one place, and it remembers what you copy. Open any item from the menu, from a shortcut, or from Spotlight.

Library is written in SwiftUI and has no third-party dependencies.

## Features

**Open anything.** Bookmarks, applications, folders, and terminal commands open from the menu bar, a keyboard shortcut, or Spotlight.

**Find it fast.** Quick Open is a search panel that finds items by name, keyword, URL, or folder. It also calculates expressions, converts units, and searches the web.

**Keep what you copy.** Clipboard history stores text, links, images, and files in every format you copied them in. Pin the items you need.

**Shortcuts for everything.** Assign a key combination, a modified click, a scroll, a pinch, a swipe, or a hot corner to any item.

**Templates.** Ask for a value each time you open an item, such as a ticket number, and insert it into a URL.

**Native.** Built with the macOS 26 design, with Share, Services, Spotlight, and a `library://` URL scheme.

## Requirements

- macOS 26 or later
- Xcode Command Line Tools. You don't need the full Xcode app.

## Build and install

Library is distributed as source. Build it on your Mac:

```bash
git clone https://github.com/deansasek/library.git
cd library
./install.sh
```

`install.sh` builds the app, quits any running copy, and installs Library in `/Applications`.

To build without installing, run `./build.sh`. The app is written to `build/Library.app`. The repository doesn't include a built app.

## Get started

1. Open Library. A short welcome tour explains the basics and asks for any access it needs.
2. Click the bookmark icon in the menu bar, or press Control-Space to open Quick Open.
3. Choose **Edit Library…** to add items. You can also drag an app from Finder, or a link from your browser, into the window.
4. Turn on **Open When You Log In** in Settings to start Library with your Mac.

## Use Library

### Open items

- Click an item in the menu to open it. Hold Option to open it the other way, such as in a new window instead of a new tab.
- An application comes to the front, or starts a new instance when it has launch arguments.
- A terminal command runs in a new Terminal window, in a login shell.

### Organize your library

- Add bookmarks (⌘N), folders (⇧⌘N), applications, commands, and dividers from the toolbar.
- Select several rows with ⌘-click or ⇧-click. Drag rows to reorder them or move them into folders.
- Right-click a row to open it, show it in Finder, get info, rename, move, share, or delete it. Press Return to rename the selected row.
- ⌘Z undoes a change, and ⇧⌘Z redoes it. Undo history lasts until you quit.

Use **Get Info** (⌘I) to edit an item's name, icon, URL or command, **Opens In** behavior, keywords, color, browser, shortcuts, and login behavior.

### Search with Quick Open

- Type words from an item's name, keywords, URL, or folder. Press ↑ or ↓ to choose a result, and press Return to open it.
- Type or paste a web address to open it, or add it to your library. Type a search to search Google.
- Press Tab, or right-click a result, to open it the other way, copy its link, path, or command, or show an app in Finder.
- Press ⌘1 through ⌘9 to open the first nine results.

### Use the clipboard

- Quick Open and the Library menu show your latest clipboard items. Choose one to copy it again.
- Pin an item to keep it after you quit.
- Library skips anything that a password manager marks as private.

### Set shortcuts

Shortcuts are global. By default, Control-click opens the menu, Control-Space opens Quick Open, and Control-Command-V opens the clipboard menu. To change them, open **Settings > Shortcuts**. You can restore the defaults there at any time.

### Use Library from other apps

- **Services:** Select a web link in any app, then choose **Services > Add to Library**.
- **Spotlight:** Bookmarks, applications, and commands appear in Spotlight results.
- **URL scheme:** Run `open "library://open?name=Jira&value=ABC-123"` to open an item and fill in its template, or `open "library://menu"` to show the menu.

## Privacy and data

Your library and clipboard history stay on your Mac. Library connects to the internet only to load favicons from the sites you bookmark and to search Google when you ask it to.

| Data | Location |
| --- | --- |
| Bookmarks, applications, folders, shortcuts, and order | `~/.library/bookmarks.json` |
| Pinned clipboard items | `~/.library/clipboard.json`, readable only by you |
| Favicon cache | `~/.library/favicons/`. Library downloads favicons again if you delete this folder. |
| Settings | macOS preferences |

Unpinned clipboard history stays in memory and is cleared when you quit. To stop recording clipboard history, turn it off in Settings.

If Library can't read `bookmarks.json`, it saves a copy as `bookmarks-damaged.json` and tells you when it launches.

Updates don't change your data, because it's stored in `~/.library`, outside the app.

## Permissions

- **Keyboard shortcuts** don't need permission.
- **Click, scroll, pinch, and swipe shortcuts** need Accessibility access so Library can intercept the input. Turn it on in **System Settings > Privacy & Security > Accessibility**.
- **Hot corners** don't need permission.

The build script uses a fixed signing identifier, so Accessibility access stays on after you rebuild. If clicks stop working after a macOS update, remove Library from Accessibility and add it again.

## Troubleshooting

- **A shortcut does nothing.** Another app may use the same key combination. Library shows a warning for conflicts in the manager. Control-Space can conflict with the macOS input source shortcut.
- **Open When You Log In has no effect.** Move `Library.app` to `/Applications` before you turn it on. The login item stores the app's location.
- **Services don't appear.** Log out and back in, or run `/System/Library/CoreServices/pbs -update`.

## Project structure

| Folder | Contents |
| --- | --- |
| `Sources/Library/App/` | Entry point, menu bar menu, app delegate (URL scheme, Spotlight, Services) |
| `Sources/Library/Model/` | Library tree, store with undo and shortcuts, opening behavior, icons |
| `Sources/Library/Clipboard/` | Clipboard history |
| `Sources/Library/QuickOpen/` | Quick Open panel, search model, results, and answers |
| `Sources/Library/Manage/` | Library window, rows, sheets, Get Info, icon picker |
| `Sources/Library/Settings/` | Settings window and shortcut fields |
| `Sources/Library/System/` | Shortcuts, hot keys, popup menu, Spotlight, favicons, login item, installer |
| `Sources/Library/Welcome/` | First-launch tour |
| `Resources/` | App icon |
| `scripts/` | `make-icon.swift`, which draws the app icon |

## Contributing

Contributions are welcome. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages, such as `feat: add clipboard search filter` or `fix: keep Quick Open focus after resize`.

1. Fork the repository and create a branch.
2. Make your change, then run `./build.sh` to confirm it builds.
3. Open a pull request that describes the change and why it's needed.
