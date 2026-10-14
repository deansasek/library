# Privacy

What Library stores, where it stores it, and what it sends over the network.

## Privacy

Library keeps your library and clipboard history on your Mac. Unpinned clipboard history stays in memory and is cleared when you quit.

The app connects to the internet only for these:

- **Favicons** from the sites you bookmark.
- **Copied GIFs**, only if you turn on **Play Copied GIFs** in **Settings > Clipboard** (off by default). Library downloads a GIF you copied from a web page so it can play.
- **Link checks**, only if you turn on **Check Links Periodically** in **Settings > General** (off by default): once a day, Library requests each bookmark's address with a HEAD request, which reads no page content.
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

