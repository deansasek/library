# Development and releasing

## Requirements

- macOS 26 or later, as `Package.swift` asks for.
- Swift 6, from the Xcode Command Line Tools. The checks and the release build need no other install, and no full Xcode.

## Development

- `./build.sh` builds the app.
- `./test.sh` runs the checks in `Tests/`. They use private pasteboards and temporary files, so they never touch your clipboard or your library.
- `Tests/render.sh` draws every screen in light and dark appearance to PNGs, so the views can be checked by eye. It needs no window server or screen-recording permission, and without a folder it writes to a temporary one it prints.
- On GitHub Actions, a pull request that changes code runs `./test.sh` and then `swift build -c release`, since `test.sh` leaves out the app entry point and resource processing. A push to `main` also builds the app and renders the screens with `Tests/render.sh`. The render check runs on `main` and on demand only, not on a pull request, since it is the slowest step. Changes to Markdown and `docs/` skip the run.

## Releasing

Push a tag to publish a release:

```bash
git tag v1.2.0
git push origin v1.2.0
```

Or run the **Release** workflow by hand with a version. Either way, GitHub Actions builds and checks the app, then publishes `Library-1.2.0.zip`. Only a commit on `main` can release: a manual run must start on `main`, and a tag must point at a commit `main` reaches. The zip is the source, with only what's needed to build. The tests, workflows, docs, scripts, `test.sh`, and `update.sh` are left out, as set in `.gitattributes`. The zip and its SHA-256 checksum are published to the same release, so the check the install command and the update check run confirms the download matches that release, and does not show the release is genuine: anyone who can replace the release assets can replace the checksum too.

If publishing fails with a server error, the workflow makes up to four attempts. Re-running it is safe, because it skips creating a release that already exists.
## Languages

Library is in English. Strings live in `Sources/Library/Resources/en.lproj/Localizable.strings`. Write each user-facing string as `Text("…", bundle: L10n.bundle)`, or `String(localized: "…", bundle: L10n.bundle)` where a `String` is needed. To add a string, add a `"key" = "value";` line with a `/* comment */` above it. Dynamic text, such as file names, counts, and clipboard contents, isn't localized.

