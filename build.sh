#!/bin/zsh
# Builds Library.app in ./build. Set VERSION to stamp a version, as the release workflow does.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
bin="$(swift build -c release --show-bin-path)/Library"

app="build/Library.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Library"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
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
    <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
    <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>com.deansasek.library</string>
        <key>CFBundleURLSchemes</key><array><string>library</string></array>
    </dict></array>
    <key>NSUserActivityTypes</key>
    <array><string>com.apple.corespotlightitem</string></array>
    <key>NSServices</key>
    <array><dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Add to Library</string></dict>
        <key>NSMessage</key><string>addBookmark</string>
        <key>NSPortName</key><string>Library</string>
        <key>NSSendTypes</key><array><string>public.utf8-plain-text</string><string>NSStringPboardType</string></array>
    </dict></array>
</dict>
</plist>
PLIST
# A fixed requirement keeps macOS permissions (Accessibility) valid across rebuilds. A plain ad-hoc
# signature changes on every build, which silently revokes them.
codesign --force --sign - --identifier com.deansasek.library \
    -r='designated => identifier "com.deansasek.library"' "$app"
echo "Built $app"
