#!/bin/zsh
# Builds Library.app in ./build. Set VERSION to stamp a version, as the release workflow does.
set -euo pipefail
cd "$(dirname "$0")"
# The version comes from VERSION, else the latest git tag, else 0.0.0. A plain build from source must not
# claim to be older than the latest release, or the update check would always offer one.
version="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
version="${version:-0.0.0}"
# The version is written into Info.plist, so only digits separated by dots pass (scripts/check-version.sh).
scripts/check-version.sh "$version" || { echo "Refusing version \"$version\": use digits separated by dots, such as 1.2.0." >&2; exit 1; }

swift build -c release
bin="$(swift build -c release --show-bin-path)/Library"

app="build/Library.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Library"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# SwiftPM puts the localized strings (from Sources/Library/Resources) in this bundle. The app reads them from here.
strings_bundle="$(swift build -c release --show-bin-path)/Library_Library.bundle"
# Without this bundle the app falls back to its main bundle, which has no translations, and nothing reports it.
[[ -d "$strings_bundle" ]] || { echo "Missing $strings_bundle: the localized strings would not be in the app." >&2; exit 1; }
cp -R "$strings_bundle" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.deansasek.library</string>
    <key>CFBundleName</key><string>Library</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>Library</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>com.deansasek.library</string>
        <key>CFBundleURLSchemes</key><array><string>library</string></array>
    </dict></array>
    <key>UTExportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>com.deansasek.library.rows</string>
        <key>UTTypeDescription</key><string>Library rows</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict></array>
    <key>NSUserActivityTypes</key>
    <array><string>com.apple.corespotlightitem</string></array>
    <key>NSServices</key>
    <array><dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Add to Library</string></dict>
        <key>NSMessage</key><string>addBookmark</string>
        <key>NSPortName</key><string>Library</string>
        <key>NSSendTypes</key><array><string>public.utf8-plain-text</string><string>NSStringPboardType</string></array>
    </dict><dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Add to Library</string></dict>
        <key>NSMessage</key><string>addFiles</string>
        <key>NSPortName</key><string>Library</string>
        <key>NSSendFileTypes</key><array><string>com.apple.application-bundle</string><string>public.folder</string></array>
        <key>NSSendTypes</key><array><string>public.file-url</string></array>
    </dict></array>
</dict>
</plist>
PLIST
# A malformed Info.plist would be installed and fail only at launch, so it is checked before anything is signed.
plutil -lint "$app/Contents/Info.plist"
# A fixed requirement keeps macOS permissions (Accessibility) valid across rebuilds. A plain ad-hoc
# signature changes on every build, which silently revokes them.
codesign --force --sign - --identifier com.deansasek.library \
    -r='designated => identifier "com.deansasek.library"' "$app"
# A bad signature would be refused by macOS on another Mac, so the strict check runs before the build is reported.
codesign --verify --strict --verbose=2 "$app"
echo "Built $app"
