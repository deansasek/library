#!/bin/zsh
# Builds Library and installs it in /Applications, replacing the old copy. Your library lives in ~/.library, apart
# from the app, so an update never touches it. Check for Updates downloads a fresh copy and removes it. A build from
# a clone leaves one folder here afterwards, the .build compile cache, which a later update.sh reuses; everything else
# this makes is removed. Delete it when you no longer want to update from this folder.
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
# Installs the Command Line Tools when they are missing. Apple's installer runs without a window when softwareupdate
# can find them, which needs an administrator password once. Otherwise the standard install window opens, and this
# waits up to 30 minutes for it to finish.
# softwareupdate -l can hang, so it gets a time limit. Apple's installer looks for the marker file at a fixed path, so the
# marker cannot have a random name. It is created only when nothing exists at that path, so a file or symlink another
# user planted there is never written through.
CLT_MARKER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

# Runs a command for at most $1 seconds, and returns 124 when the limit stops it.
run_with_timeout() {
    local secs="$1"
    shift
    "$@" &
    local pid=$! rc=0 i
    for (( i = 0; i < secs * 2; i++ )); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 124
    fi
    wait "$pid" || rc=$?
    return $rc
}

ensure_command_line_tools() {
    xcode-select -p >/dev/null 2>&1 && return 0
    print "The Xcode Command Line Tools are needed to build Library. Installing them now."
    local made_marker=0 listing label
    rm -f "$CLT_MARKER" 2>/dev/null || true
    if ( set -C; : > "$CLT_MARKER" ) 2>/dev/null; then
        made_marker=1
    fi
    listing="$(mktemp)"
    run_with_timeout 60 softwareupdate -l >"$listing" 2>/dev/null || true
    label="$(sed -n 's/^[*] Label: *//p' "$listing" | grep 'Command Line Tools' | tail -1 || true)"
    rm -f "$listing"
    if [[ -n "$label" ]]; then
        sudo softwareupdate -i "$label" --verbose || true
    fi
    if (( made_marker )); then
        rm -f "$CLT_MARKER"
    fi
    if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install 2>/dev/null || true
        print "Finish the window that opened. Waiting for the tools to install."
        for _ in {1..360}; do
            xcode-select -p >/dev/null 2>&1 && break
            sleep 5
        done
    fi
    xcode-select -p >/dev/null 2>&1 || fail "the Xcode Command Line Tools did not install. Run 'xcode-select --install', finish the window, then run the install again."
}
ensure_command_line_tools
command -v swift >/dev/null 2>&1 || fail "the Swift compiler was not found. Reinstall the Xcode Command Line Tools with 'xcode-select --install'."

if ! ./build.sh; then
    fail "the build failed. The messages above show where."
fi

# Only replace a copy that is Library. An unrelated app that happens to be named Library.app is left alone, the same
# way the in-app Installer refuses to replace it. The check runs before anything is quit, copied, or moved, so a
# refusal leaves Applications exactly as it was.
if [[ -e /Applications/Library.app ]]; then
    existing_id="$(defaults read /Applications/Library.app/Contents/Info CFBundleIdentifier 2>/dev/null || true)"
    [[ "$existing_id" == "com.deansasek.library" ]] || fail "Applications already has a different app named Library.app. Move it out of the way yourself, then try again. Nothing was changed."
fi

# Quit the running app through its own quit command, so it saves pending changes on the way out. A signal such as
# SIGTERM skips those saves. Wait a bounded time for it to exit, so a stuck app cannot stall the install forever.
quit_library() {
    pgrep -x Library >/dev/null || return 0
    osascript -e 'tell application id "com.deansasek.library" to quit' 2>/dev/null || true
    for _ in {1..75}; do
        pgrep -x Library >/dev/null || return 0
        sleep 0.2
    done
}
quit_library
if pgrep -x Library >/dev/null; then
    fail "Library is still running. Quit it from the menu bar, wait for it to close, then try again."
fi

# Copy the new app beside the old one in /Applications (same volume, so the moves are renames), check the copy, and only
# then swap it in. The old copy goes to the Trash last, so a failed copy leaves the installed app as it was.
staging="/Applications/.Library.new.$$.app"
previous="/Applications/.Library.old.$$.app"
trap 'rm -rf "$staging"' EXIT
rm -rf "$staging"
cp -R build/Library.app "$staging" || fail "the copy into Applications failed."

# Check the copy reports the version we built, so a bad copy is caught before it replaces the installed app.
built="$(defaults read "$PWD/build/Library.app/Contents/Info" CFBundleShortVersionString)"
copied="$(defaults read "$staging/Contents/Info" CFBundleShortVersionString)"
[[ "$built" == "$copied" ]] || fail "the copy in Applications reports version $copied, not $built."

had_previous=0
if [[ -e /Applications/Library.app ]]; then
    mv /Applications/Library.app "$previous" || fail "the installed copy could not be moved aside."
    had_previous=1
fi
if ! mv "$staging" /Applications/Library.app; then
    if (( had_previous )); then
        mv "$previous" /Applications/Library.app || print -u2 "The previous copy is at $previous. Move it back to Applications."
    fi
    fail "the new copy could not be put in place."
fi
# The old copy goes to the Trash so it can be recovered, rather than being deleted. Its version in the name keeps it
# easy to recognise in the Trash, and a unique name is used if a copy is already there so nothing is overwritten.
if (( had_previous )); then
    old_version="$(defaults read "$previous/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
    trashed="$HOME/.Trash/Library${old_version:+ $old_version}.app"
    if [[ -e "$trashed" ]]; then
        trashed="$HOME/.Trash/Library.old.$$.app"
    fi
    if [[ -d "$HOME/.Trash" ]] && mv "$previous" "$trashed" 2>/dev/null; then
        print "The previous copy is in the Trash: $(basename "$trashed")"
    else
        print -u2 "Installed, but the old copy could not be moved to the Trash: $previous"
    fi
fi
installed="$(defaults read /Applications/Library.app/Contents/Info CFBundleShortVersionString)"

# Opening the app is a convenience. A failure here does not undo a good install.
open /Applications/Library.app 2>/dev/null || print -u2 "Installed, but Library did not open. Open it from Applications."
# build/Library.app is the only thing this leaves behind that is not needed afterward, since Check for Updates
# downloads a fresh copy anyway. Removing it keeps the header above true for a build from a clone. The .build cache is
# kept, so a later update.sh does not have to compile everything again.
rm -rf build 2>/dev/null || true
echo "Installed Library $installed in /Applications."
