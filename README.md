<div align="center">

<img src="docs/AppIcon.png" width="128" height="128" alt="Library app icon">

<h1>Library</h1>

<p><strong>Everything you open and copy, one shortcut away.</strong></p>

</div>

<p align="center">
  <img src="docs/media/quick_open.gif" width="640" alt="Quick Open finding a bookmark as you type">
</p>

Library lives in your menu bar. Keep your bookmarks, apps, folders, and commands in one place, open any of them from a shortcut, and find anything you copied a moment ago.

## Install

Paste this into Terminal:

```bash
git clone https://github.com/deansasek/library.git "$HOME/Library/Application Support/Library/Source" && "$HOME/Library/Application Support/Library/Source/install.sh"
```

Library is installed in your Applications folder. It needs macOS 26 or later and the Xcode Command Line Tools. Library checks for updates itself, and **Check for Updates…** installs them.

## Get started

1. Press Control-Space to open Quick Open. Type a name and press Return.
2. Choose **Edit Library…** from the menu bar icon to add bookmarks and apps.
3. Turn on **Open at Login** in **Settings > General** to have Library start with your Mac.

## What you can do

- **Open anything fast.** Bookmarks, apps, folders, and commands open from the menu, a shortcut, or Spotlight.
- **Find it in Quick Open.** Search across your library, your clipboard, and your snippets.
- **Keep what you copy.** Every copy is kept, with pins, previews, and a paste queue.
- **Save snippets.** Reuse text you type often.
- **Organize.** Folders, duplicates, bulk edits, and import from Safari or Chrome.

The [guide](docs/guide.md) covers every feature and setting.

## Privacy

Your library and clipboard history stay on your Mac. Library contacts the internet only to load site icons, to check for updates, and, if you choose, to sync your library through iCloud Drive. The [privacy guide](docs/privacy.md) lists exactly what is stored and sent.

## Documentation

- [Guide](docs/guide.md): every feature, setting, and permission
- [Privacy](docs/privacy.md): what is stored, where, and what is sent
- [Development and releasing](docs/development.md): building, testing, and publishing
