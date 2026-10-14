<div align="center">

<img src="docs/AppIcon.png" width="128" height="128" alt="Library app icon">

# Library

Everything you open and copy, one shortcut away.

</div>

Library is a menu bar app for macOS. Keep your bookmarks, apps, folders, and terminal commands in one place, and open any of them from the menu, a shortcut, or Spotlight. Library also remembers what you copy.

## Requirements

- macOS 26 or later
- Xcode Command Line Tools

## Install

Library is distributed as source. Build and install it with:

```bash
git clone https://github.com/deansasek/library.git
cd library
./install.sh
```

To build without installing, run `./build.sh`. The app is written to `build/Library.app`.

## Getting started

1. Open Library and follow the welcome tour.
2. Click the bookmark icon in the menu bar, or press Control-Space for Quick Open.
3. Choose **Edit Library…** to add items. You can also drag an app or a link into the window.

## Features

- **Open anything.** Bookmarks, apps, folders, and terminal commands open from the menu, a shortcut, or Spotlight.
- **Quick Open.** Search by name, keyword, URL, or folder. It also calculates, converts units, and searches the web.
- **Clipboard history.** Keeps text, links, images, and files. Pin the items you need.
- **Shortcuts.** Assign key combinations, clicks, scrolls, swipes, or hot corners to any item.
- **Templates.** Enter a value each time you open an item, such as a ticket number.

### Shortcuts

- Control-click opens the menu.
- Control-Space opens Quick Open.
- Control-Command-V opens the clipboard menu.

Change them in **Settings > Shortcuts**.

### From other apps

- **Services:** Select a link, then choose **Services > Add to Library**.
- **URL scheme:** `open "library://open?name=Jira&value=ABC-123"` opens an item. `open "library://menu"` shows the menu.

## Privacy

Your library and clipboard history stay on your Mac. Library connects to the internet only to load favicons from your bookmarked sites and to search Google when you ask.

Data is stored in `~/.library/`. Updates don't touch it.

## Permissions

- **Click, scroll, pinch, and swipe shortcuts** need Accessibility access. Turn it on in **System Settings > Privacy & Security > Accessibility**.

## Troubleshooting

- **A shortcut does nothing.** Another app may use the same keys. Check **Settings > Shortcuts** for a conflict.
- **Open When You Log In has no effect.** Move `Library.app` to `/Applications` first.
- **Services are missing.** Log out and back in.

## Contributing

Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages. Run `./build.sh` before you open a pull request.
