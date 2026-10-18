# Library guide

A complete reference for every feature, setting, and permission. For a quick overview, see the [README](../README.md).

## Features

### Open anything

Bookmarks, apps, folders, and terminal commands open from the menu bar, a keyboard shortcut, or Spotlight. Hold Option while you click to open an item the other way.

- **Bookmarks** open in a new tab or a new window.
- **Apps** come to the front. Add launch arguments, such as `--profile work`, to start a new instance.
- **Terminal commands** run in a login shell in a new Terminal window. Add only commands you trust.
- **Folders** open all of their bookmarks and apps at once. Library asks first when there are more than five. To hide the Open All item in a folder's menus, turn off **Show Open All** when you create or edit the folder.

### Find it with Quick Open

Press Control-Space to search everything in your library.

- Type words from a name, keyword, URL, or folder. Press ↑ or ↓, then Return.
- Type or paste a web address to open it, or add it to your library.
- Press Tab, or right-click a result, to open it the other way, copy its link, path, or command, or, for an app, show it in Finder.
- Press ⌘1 through ⌘9 to open the first nine results.

### Keep what you copy

<p align="center">
  <img src="docs/media/clipboard_menu.png" width="640" alt="The Library clipboard menu listing recent copies, with numbered shortcuts">
</p>

Library remembers what you copy, including text, links, images, and files, in the formats you copied them in, keeping one copy of each image.

- Open the **Library** menu or Quick Open to see your latest copies. Choose one to copy it again.
- Pin an item to keep it after you quit.
- Press Control-Command-V to open the clipboard menu at the pointer. Press 1 through 9 to copy an item, or hold Option to copy it as plain text.
- When a text field has the keyboard, choosing an item pastes it. Otherwise it copies. Turn this off with **Paste into text fields** in **Settings > Clipboard**. Pasting needs Accessibility access.
- Select an item in Quick Open and press Space to preview it in Quick Look.
- Copy a link and Library removes tracking codes, such as `utm_source`, `fbclid`, and `gclid`, so the link you paste is clean. Turn this off in **Settings > General**. The link in your history isn't changed.
- Copy as lower or upper case, trimmed, with its lines joined, or with smart punctuation. Copy a bookmark as a Markdown link. All are in Quick Open, under Tab.
- Text with an address, a phone number, or a date gets Open in Maps, Copy Phone Number, or Add to Calendar in Quick Open, under Tab. Detection happens on this Mac.
- Type `from Safari` in Quick Open to see only what you copied in Safari.
- Build a paste queue. Add several items, then paste them one at a time, in order.
- Library keeps the 50 most recent unpinned copies, up to 200 MB of them. Pinned items stay.
- Turn on **Play copied GIFs** in **Settings > Clipboard** (off by default) to download the GIF behind a copied image so it plays.
- Turn on **Require Touch ID or password to show pinned items** in **Settings > Clipboard** (off by default) to hide pinned items until you authenticate. **Lock Pinned Items** in the Library menu hides them again.
- Turn on **Put the Latest Item on the Clipboard When Library Opens** in **Settings > Clipboard** to copy the newest saved item at launch. It needs **Keep clipboard history across restarts**.
- When the clipboard holds a link or app that is not in your library, the menu and Quick Open offer to add it.

Library skips anything a password manager marks as private, and copies over 25 MB.

### Save snippets

Keep text you type often, such as an address or a standard reply, as a snippet. Add one from **File > New Snippet…** or the **Snippets** button in the Library window. Type a snippet's name or keywords in Quick Open, then press Return to copy it.

In the Snippets sheet, Return opens the selected snippet for editing, and Delete asks before it is removed. Snippets have no Recently Deleted folder, but ⌘Z right after a delete brings the snippet back with its name, keywords, and text.

### Organize your library

<p align="center">
  <img src="docs/media/manager_window.png" width="640" alt="The Edit Library window with folders, apps, and a bookmark">
</p>

Choose **Edit Library…** to manage everything in one window.

- Add items from the **+** menu, or drag an app or a link into the window.
- Select several rows to move, reorder, or edit them together. Changes you make in bulk are a single undo step.
- Right-click a row to open it, edit or rename it, move, share, or delete it. An app can also be shown in Finder.
- Deleted items go to **Recently Deleted**, where you can restore them or delete them for good. They are removed for good after 30 days.
- Find and merge duplicate bookmarks from **File > Find Duplicates…**.
- Import bookmarks from Safari or Chrome with **File > Import Bookmarks…**. They go into one folder, and ⌘Z undoes the import.
- Export and restore your whole library from **Settings > General**.

Add a bookmark to the **Reading List** from its right-click menu, or from Tab in Quick Open. Unread bookmarks are listed first. Removing a bookmark from the Reading List leaves it in the library.

Turn on **Check links periodically** in **Settings > General** (off by default) to request each bookmark's address once a day, with a HEAD request, which reads no page content. A bookmark whose page fails or can't be reached gets a warning in Edit Library. **Check Links** in the File menu checks now.

Use ⌘Z to undo and ⇧⌘Z to redo.

### Edit an item

<p align="center">
  <img src="docs/media/get_info.png" width="640" alt="The Get Info sheet for a bookmark, with name, URL, and template settings">
</p>

Select an item and press ⌘I, or choose **Edit…** from the toolbar or a right-click menu.

- **Name and icon.** Pick an SF Symbol or an emoji, or keep the site's favicon or the app's icon.
- **URL or command**, how a click opens it, and which browser to use.
- **Keywords** help Quick Open and Spotlight find it.
- **Color** adds a dot in the menu and the Library window.
- **Shortcuts** can be added to any item.
- **Open When You Log In** opens it a few seconds after you log in.
- **Notes** appear under the name in Quick Open and in Spotlight.

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

Library checks GitHub for a new release every hour while it runs, and when it starts if the last check was an hour or more ago. When there's a newer version, a single item appears at the top of the menu. Nothing pops up. Turn this off in **Settings > General**, or choose **Check for Updates…** at any time. See [Privacy](privacy.md) for exactly what is sent.

## Settings

Press ⌘, to open Settings. General holds startup, iCloud Drive, updates, backup and restore, names for new bookmarks, link checks, and link cleaning. **Name new bookmarks from their pages** is off by default. When it is on, a new bookmark takes its page's title. Shortcuts sets the global keys for the menu, Quick Open, the clipboard, and Open Copied Link, and where the Library menu opens: at the pointer or from the menu bar. Clipboard controls history, pasting, GIFs, the lock, and keeping history across restarts.

<p align="center">
  <img src="docs/media/settings_general.png" width="640" alt="Settings, General tab, with storage, updates, backup, and tracking options">
</p>

## Permissions

- **Keyboard shortcuts**, **hot corners**, Quick Open, and the menus don't need any permission.
- **Click, scroll, pinch, and swipe shortcuts**, **pasting into text fields**, and **suggesting a selected link** need Accessibility access. Turn it on in **System Settings > Privacy & Security > Accessibility**. Library reads your selection only when you open one of its menus or Quick Open, and it doesn't keep it.

## Troubleshooting

- **A shortcut doesn't work.** Another app may use the same keys. Check **Settings > Shortcuts**. Control-Space can conflict with the macOS input source shortcut.
- **Clicks stop working after a macOS update.** Remove Library from Accessibility, then add it again.
- **Open at login has no effect.** Move `Library.app` to `/Applications` first. The login item remembers the app's location.
- **Services don't appear.** Log out and back in, or run `/System/Library/CoreServices/pbs -update`.

