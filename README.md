<div align="center">

<img src="docs/AppIcon.png" width="128" height="128" alt="Library app icon">

<h1>Library</h1>

<p><strong>Everything you open and copy, one shortcut away.</strong></p>

</div>

Library lives in your menu bar. Keep your bookmarks, apps, folders, and terminal commands in one place, open any of them from the menu or a shortcut, and bring back anything you copied a moment ago.

<p align="center">
  <img src="docs/media/quick_open.gif" width="640" alt="Quick Open finding a bookmark as you type">
</p>

<p align="center">
  <img src="docs/media/menu_bar.gif" width="640" alt="The Library menu opening and closing from the menu bar">
</p>

## Features

### Open anything

Bookmarks, apps, folders, and terminal commands open from the menu bar, a keyboard shortcut, or Spotlight. Hold Option while you click to open an item the other way.

- **Bookmarks** open in a new tab or a new window.
- **Apps** come to the front. Add launch arguments, such as `--profile work`, to start a new instance.
- **Terminal commands** run in a login shell in a new Terminal window. Add only commands you trust.
- **Folders** open all of their bookmarks and apps at once. Library asks first when there are more than five.

### Find it with Quick Open

Press Control-Space to search everything in your library.

- Type words from a name, keyword, URL, or folder. Press ↑ or ↓, then Return.
- Type or paste a web address to open it, or add it to your library.
- Press Tab, or right-click a result, to open it the other way, copy its link, path, or command, or show it in Finder.
- Press ⌘1 through ⌘9 to open the first nine results.

### Keep what you copy

Library remembers what you copy, including text, links, images, and files, in every format you copied them in.

- Open the **Library** menu or Quick Open to see your latest copies. Choose one to copy it again.
- Pin an item to keep it after you quit.
- Press Control-Command-V to open the clipboard menu at the pointer. Press 1 through 9 to copy an item, or hold Option to copy it as plain text.
- When a text field has the keyboard, choosing an item pastes it. Otherwise it copies. Turn this off with **Paste Into Text Fields** in **Settings > Clipboard**. Pasting needs Accessibility access.
- Select an item in Quick Open and press Space to preview it in Quick Look.
- Copy a link and Library removes tracking codes, such as `utm_source`, `fbclid`, and `gclid`, so the link you paste is clean. Turn this off in **Settings > General**. The link in your history isn't changed.
- Copy as lower or upper case, trimmed, or with its lines joined. Copy a bookmark as a Markdown link. Both are in Quick Open, under Tab.
- Type `from Safari` in Quick Open to see only what you copied in Safari.
- Build a paste queue. Add several items, then paste them one at a time, in order.

Library skips anything a password manager marks as private, and copies over 25 MB.

### Save snippets

Keep text you type often, such as an address or a standard reply, as a snippet. Add one from **File > New Snippet…** or the **Snippets** button in the Library window. Type a snippet's name or keywords in Quick Open, then press Return to copy it.

### Organize your library

Choose **Edit Library…** to manage everything in one window.

- Add items from the **+** menu, or drag an app or a link into the window.
- Select several rows to move, reorder, or edit them together. Changes you make in bulk are a single undo step.
- Right-click a row to open it, show it in Finder, get info, rename, move, share, or delete it.
- Find and merge duplicate bookmarks from **File > Find Duplicates…**.
- Import bookmarks from Safari or Chrome with **File > Import Bookmarks…**. They go into one folder, and ⌘Z undoes the import.
- Export and restore your whole library from **Settings > General**.

Use ⌘Z to undo and ⇧⌘Z to redo.

### Edit an item

Select an item and press ⌘I, or choose **Edit…** from the toolbar or a right-click menu.

- **Name and icon.** Pick an SF Symbol or an emoji, or keep the site's favicon or the app's icon.
- **URL or command**, how a click opens it, and which browser to use.
- **Keywords** help Quick Open and Spotlight find it.
- **Color** adds a dot in the menu and the Library window.
- **Shortcuts** can be added to any item.
- **Open When You Log In** opens it a few seconds after you log in.

### Use templates

Put `{}` in a URL where a value goes, and Library asks for it when you open the bookmark. For several values, name them: `{project}` or `{id:Issue number}`. Library asks for all of them in one sheet.

### Shortcuts

Each shortcut can be a key combination, a modified click, a scroll, a pinch, a swipe, or a hot corner. Keys need Control, Option, or Command. An item can have several shortcuts.

The defaults are Control and right-click for the menu, Control-Space for Quick Open, and Control-Command-V for the clipboard menu. Change them in **Settings > Shortcuts**.

### Work with other apps

- **Spotlight** finds your bookmarks, apps, and commands.
- **Services:** select a link in any app, then choose **Services > Add to Library**. In Finder, select apps or folders and choose the same item.
- **Share:** right-click a bookmark or app and choose **Share…**. Drag a row into any app to drop its link or file.
- **URL scheme:** `library://open?name=Jira&value=ABC-123` opens a bookmark and fills its template. `library://menu` shows the menu, and `library://search` opens Quick Open. Terminal commands can't be opened this way, so a web page can't run one.
- **Shortcuts app:** actions for opening and searching items, adding bookmarks and apps, Frequently Used, and the clipboard. Run Terminal Command always asks first. These appear in the Shortcuts app only in a build that includes App Intents metadata, which Xcode generates. `./build.sh` doesn't yet.

### Stay up to date

Library checks GitHub for a new release every hour while it runs, and when it starts if the last check was an hour or more ago. When there's a newer version, a single item appears at the top of the menu. Nothing pops up. Turn this off in **Settings > General**, or choose **Check for Updates…** at any time. See [Privacy](#privacy) for exactly what is sent.

## Install

### Download the source

1. Download the latest `Library-x.y.z.zip` from [Releases](https://github.com/deansasek/library/releases). It holds the source, not a built app.
2. Unzip it and open the folder in Terminal.
3. Run `./install.sh`. It builds Library on your Mac and copies it to your Applications folder.

Because you build it yourself, macOS opens it without a security warning. To update, download the new zip and run `./install.sh` again.

### Clone the repository

```bash
git clone https://github.com/deansasek/library.git
cd library
./install.sh
```

To build without installing, run `./build.sh`. The app is written to `build/Library.app`. To update, run `./update.sh`. It stops if you have uncommitted changes or aren't on `main`. Otherwise it fast-forwards `main` from `origin` (it never resets or force-pushes), shows the version before and after, and runs `./install.sh`. `DRY_RUN=1 ./update.sh` shows the commands without running them.

**Requirements:** macOS 26 or later, and the Xcode Command Line Tools.

## Getting started

1. Open Library. A short welcome tour explains the basics and asks for any access it needs.
2. Click the bookmark icon in the menu bar, or press Control-Space.
3. Choose **Edit Library…** to add items.
4. Turn on **Open at Login** in **Settings > General** to start Library when you log in.

## Privacy

Library keeps your library and clipboard history on your Mac. Unpinned clipboard history stays in memory and is cleared when you quit.

The app connects to the internet only for these:

- **Favicons** from the sites you bookmark.
- **Copied GIFs**, only if you turn on **Play Copied GIFs** in **Settings > Clipboard** (off by default). Library downloads a GIF you copied from a web page so it can play.
- **Update checks** to `https://api.github.com/repos/deansasek/library/releases/latest`. This happens when you choose **Check for Updates…**, and every hour when automatic checks are on (the default). The request names only the app's version, in its User-Agent header, and the ETag from GitHub's last answer, so unchanged checks cost nothing. No account or other data is sent.

**Touch ID or password lock.** Turn on **Require Touch ID or password to show pinned items** in **Settings > Clipboard** (off by default). Pinned items stay hidden until you authenticate. The unlock lasts in memory until you choose **Lock Pinned Items**, the Mac sleeps, or Library quits. Search doesn't look inside locked items. If the Mac has no password and no Touch ID, Library won't turn the lock on and explains how to add one.

**Your files** are in `~/.library/`:

| File | Contents |
| --- | --- |
| `bookmarks.json` | Your items, folders, shortcuts, and order |
| `clipboard.json` | Pinned clipboard items, encrypted with a key kept in your Keychain |
| `snippets.json` | Your snippets, as plain text. They are not encrypted. Don't keep passwords in a snippet. |
| `favicons/` | Cached site icons. Library downloads them again if you delete the folder. |

**Keep Library in iCloud Drive** (**Settings > General**, off by default) moves `bookmarks.json` into iCloud Drive and links to it from `~/.library`, so your library follows you to your other Macs. Clipboard history never leaves your Mac. If two Macs change the library at once, the newer change wins for each item, and Library tells you when a change from another Mac replaced an edit you hadn't saved.

If Library can't read `bookmarks.json`, it saves a copy as `bookmarks-damaged.json` and tells you when it launches. Updates don't change your data.

## Permissions

- **Keyboard shortcuts**, **hot corners**, Quick Open, and the menus don't need any permission.
- **Click, scroll, pinch, and swipe shortcuts**, **pasting into text fields**, and **suggesting a selected link** need Accessibility access. Turn it on in **System Settings > Privacy & Security > Accessibility**. Library reads your selection only when you open one of its menus, and it doesn't keep it.

## Troubleshooting

- **A shortcut doesn't work.** Another app may use the same keys. Check **Settings > Shortcuts**. Control-Space can conflict with the macOS input source shortcut.
- **Clicks stop working after a macOS update.** Remove Library from Accessibility, then add it again.
- **Open at Login has no effect.** Move `Library.app` to `/Applications` first. The login item remembers the app's location.
- **Services don't appear.** Log out and back in, or run `/System/Library/CoreServices/pbs -update`.

## Languages

Library is in English. Strings live in `Sources/Library/Resources/en.lproj/Localizable.strings`. Write each user-facing string as `Text("…", bundle: L10n.bundle)`, or `String(localized: "…", bundle: L10n.bundle)` where a `String` is needed. To add a string, add a `"key" = "value";` line with a `/* comment */` above it. Dynamic text, such as file names, counts, and clipboard contents, isn't localized.

## Development

- `./build.sh` builds the app.
- `./test.sh` runs the checks in `Tests/`. They use private pasteboards and temporary files, so they never touch your clipboard or your library.
- Every pull request and every push to `main` builds the app and runs the checks on GitHub Actions.

## Releasing

Push a tag to publish a release:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Or run the **Release** workflow by hand with a version. Either way, GitHub Actions builds and checks the app, then publishes `Library-1.2.0.zip`. The zip is the source, with only what's needed to build. The tests, workflows, docs, and icon script are left out, as set in `.gitattributes`.

If publishing fails with a server error, the workflow retries up to four times. Re-running it is safe, because it skips creating a release that already exists.
