# Privacy

What Library stores, where it stores it, and what it sends over the network.

## Privacy

Library keeps your library and clipboard history on your Mac. Unpinned clipboard history stays in memory and is cleared when you quit, unless you turn on **Keep clipboard history across restarts**.

The app connects to the internet only for these:

- **Favicons** from the sites you bookmark.
- **Copied GIFs**, only if you turn on **Play copied GIFs** in **Settings > Clipboard** (off by default). Library downloads a GIF you copied from a web page so it can play.
- **Link checks**, only if you turn on **Check links periodically** in **Settings > General** (off by default): once a day, Library quickly checks that each bookmark's page is still there. It doesn't download the page. If a site doesn't answer that check, Library loads the page and reads only its first 64 KB.
- **Update checks** to `https://api.github.com/repos/deansasek/library/releases/latest`. This happens when you choose **Check for Updates…**, every hour while Library runs when automatic checks are on (the default), and at launch when the last check was an hour or more ago. The request names only the app's version, in its User-Agent header, and the ETag from GitHub's last answer, so unchanged checks cost nothing. No account or other data is sent.
- **Update in Terminal**, only when you choose it: the release is cloned from `https://github.com/deansasek/library.git` into a temporary folder, which is deleted afterward.

**Touch ID or password lock.** Turn on **Require Touch ID or password to show pinned items** in **Settings > Clipboard** (off by default). Pinned items stay hidden until you authenticate. The unlock lasts in memory until you choose **Lock Pinned Items**, the Mac sleeps, or Library quits. Search doesn't look inside locked items. If the Mac has no password and no Touch ID, Library won't turn the lock on and explains how to add one.

**Your files** are in `~/.library/`:

| File | Contents |
| --- | --- |
| `bookmarks.json` | Your items, folders, shortcuts, and order |
| `clipboard.json` | Pinned clipboard items, encrypted with a key kept in your Keychain |
| `clipboard-history.json` | Unpinned clipboard history, encrypted the same way. Only exists when **Keep clipboard history across restarts** is on (off by default). |
| `snippets.json` | Your snippets, as plain text. They are not encrypted. Don't keep passwords in a snippet. |
| `bookmarks-before-iCloud.json`, `bookmarks-iCloud-replaced.json` | Backups kept when **Keep Library in iCloud Drive** is turned on, so no library is lost |
| `bookmarks-damaged-<time>.json` | A copy of a `bookmarks.json` that could not be read. Library tells you when it launches. |
| `snippets-damaged-<time>.json` | A copy of a `snippets.json` that could not be read |
| `clipboard-damaged-<time>.bin`, `clipboard-history-damaged-<time>.bin` | A clipboard file that could not be read, moved aside |
| `favicons/` | Cached site icons. Library downloads them again if you delete the folder. |

**Keep Library in iCloud Drive** (**Settings > General**, off by default) moves `bookmarks.json` into the `Library` folder of iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/Library/`) and links to it from `~/.library`, so your library follows you to your other Macs. Clipboard history never leaves your Mac. If two Macs change the library at once, the newer change wins for each item, and Library tells you when a change from another Mac replaced an edit you hadn't saved.

If Library can't read `bookmarks.json`, it saves a copy as `bookmarks-damaged-<time>.json` and tells you when it launches. Updates don't change your data.

Some files are written briefly to the system's temporary folder and then removed. A copy of a clip is written while you preview it in Quick Look. A terminal command is written as a script that deletes itself when Terminal runs it. A calendar event is written as an `.ics` file for Calendar. **Export** writes a backup file to the place you choose; it does not include clipboard items.

