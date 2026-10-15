#!/bin/zsh
# Builds Library and installs it in /Applications, replacing the old copy. Your library lives in ~/.library, apart
# from the app, so an update never touches it. Nothing is kept from this folder afterward: Check for Updates downloads
# a fresh copy and removes it.
#
# If anything fails before the copy, the installed app is left as it was.
set -euo pipefail
cd "$(dirname "$0")"

fail() {
    print -u2 "Library was not installed: $1"
    print -u2 "Your current copy in Applications is unchanged. Fix the problem above and run the install again."
    exit 1
}

# Check what the build needs before building, so the error names the cause.
[[ "$(uname)" == "Darwin" ]] || fail "Library only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 26 )) || fail "Library needs macOS 26 or later. This Mac runs macOS $(sw_vers -productVersion)."
xcode-select -p >/dev/null 2>&1 || fail "the Xcode Command Line Tools are missing. Run 'xcode-select --install', wait for it to finish, then try again."
command -v swift >/dev/null 2>&1 || fail "the Swift compiler was not found. Reinstall the Xcode Command Line Tools with 'xcode-select --install'."

if ! ./build.sh; then
    fail "the build failed. The messages above show where."
fi

# Quit the running app, and wait a bounded time for it to exit, so a stuck app cannot stall the install forever.
pkill -x Library || true
for _ in {1..75}; do
    pgrep -x Library >/dev/null || break
    sleep 0.2
done
if pgrep -x Library >/dev/null; then
    fail "Library is still running. Quit it from the menu bar, then try again."
fi

rm -rf /Applications/Library.app
cp -R build/Library.app /Applications/Library.app

# Check the installed copy reports the version we built, so a bad copy is caught here.
built="$(defaults read "$PWD/build/Library.app/Contents/Info" CFBundleShortVersionString)"
installed="$(defaults read /Applications/Library.app/Contents/Info CFBundleShortVersionString)"
[[ "$built" == "$installed" ]] || fail "the copy in Applications reports version $installed, not $built."

# Opening the app is a convenience. A failure here does not undo a good install.
open /Applications/Library.app 2>/dev/null || print -u2 "Installed, but Library did not open. Open it from Applications."
echo "Installed Library $installed in /Applications."
