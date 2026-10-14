# Development and releasing

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
## Languages

Library is in English. Strings live in `Sources/Library/Resources/en.lproj/Localizable.strings`. Write each user-facing string as `Text("…", bundle: L10n.bundle)`, or `String(localized: "…", bundle: L10n.bundle)` where a `String` is needed. To add a string, add a `"key" = "value";` line with a `/* comment */` above it. Dynamic text, such as file names, counts, and clipboard contents, isn't localized.

