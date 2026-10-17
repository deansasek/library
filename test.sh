#!/bin/zsh
# Lints the theming rules, then compiles the checks in Tests/ together with the app's source, except the file that
# starts the app, and runs them.
# Tests/Bench also prints timings for a 5,000-item library. The timings never fail the run.
# They use private pasteboards and temporary files, so they never touch your clipboard or your library.
set -euo pipefail
cd "$(dirname "$0")"

# The theming rules: colors, fonts, opacity on text, and icon-only buttons (Tests/lint-theming.sh).
Tests/lint-theming.sh

# The version check that build.sh and the release workflow use: valid versions pass, and text that could reach
# GITHUB_ENV or Info.plist fails.
for version in 1 1.2 1.2.0 10.20.30; do
  scripts/check-version.sh "$version"
done
for version in "" 1. .1 1..2 "1.2 3" $'1.2.0\nFOO=bar' v1.2 '1.2</string>' 1.2-beta; do
  if scripts/check-version.sh "$version"; then
    echo "FAIL: the version check accepted [$version]" >&2
    exit 1
  fi
done

# The version lookup that build.sh stamps and update.sh reports (scripts/version.sh) is run against a repository with
# no tags, one with a tag, and one whose VERSION file a release zip added. The no-tag run must fail, so a source build
# is never stamped 0.0.0 and the update check never always offers the latest release.
version_repo="$(mktemp -d)"
trap 'rm -rf "$version_repo"' EXIT
version_script="$PWD/scripts/version.sh"
git -C "$version_repo" init -q
git -C "$version_repo" -c user.email=checks@example.com -c user.name=Checks commit -q --allow-empty -m checks
if (cd "$version_repo" && env -u VERSION "$version_script" >/dev/null 2>&1); then
  echo "FAIL: the version lookup resolved with no tag and no VERSION file" >&2
  exit 1
fi
git -C "$version_repo" tag v9.9.9
tagged="$(cd "$version_repo" && env -u VERSION "$version_script")"
[[ "$tagged" == "9.9.9" ]] || { echo "FAIL: the version lookup printed [$tagged] for tag v9.9.9" >&2; exit 1; }
printf '1.2.3\n' > "$version_repo/VERSION"
from_file="$(cd "$version_repo" && env -u VERSION "$version_script")"
[[ "$from_file" == "1.2.3" ]] || { echo "FAIL: the version lookup printed [$from_file] for a VERSION file of 1.2.3" >&2; exit 1; }
echo "Version lookup: no tag fails, tag v9.9.9 reads 9.9.9, a VERSION file reads 1.2.3"

# The names build.sh writes into Info.plist that the code depends on must exist in the code, so a rename on one side
# fails here: the Services messages (NSMessage), the library URL scheme, and the exported drag type.
# Each name is read from build.sh's heredoc and searched for in the code that uses it.
plist="build.sh"
app_code="Sources/Library/App/AppDelegate.swift"
drag_code="Sources/Library/Manage/RowDrag.swift"
messages=(${(f)"$(grep -oE '<key>NSMessage</key><string>[^<]+' "$plist" | sed 's/.*<string>//' || true)"})
scheme="$(grep -oE 'CFBundleURLSchemes</key><array><string>[^<]+' "$plist" | sed 's/.*<string>//' || true)"
drag_type="$(grep -oE 'UTTypeIdentifier</key><string>[^<]+' "$plist" | sed 's/.*<string>//' || true)"
[[ ${#messages[@]} -gt 0 && -n "$scheme" && -n "$drag_type" ]] || { echo "Info.plist names not found in $plist" >&2; exit 1; }
for message in $messages; do
    grep -qF "@objc func $message(" "$app_code" || { echo "Services message $message is not an @objc func in $app_code" >&2; exit 1; }
done
grep -qF "url.scheme == \"$scheme\"" "$app_code" || { echo "URL scheme $scheme is not handled in $app_code" >&2; exit 1; }
grep -qF "UTType(exportedAs: \"$drag_type\")" "$drag_code" || { echo "Drag type $drag_type is not declared in $drag_code" >&2; exit 1; }
echo "Info.plist names match the code: ${#messages[@]} Services messages, scheme $scheme, drag type $drag_type"

sources=(${(f)"$(find Sources/Library -name '*.swift' ! -name LibraryApp.swift)"})
out="$(mktemp -d)"
trap 'rm -rf "$out" "$version_repo"' EXIT

swiftc -swift-version 6 -O $sources Tests/Checks/main.swift Tests/Bench/*.swift -o "$out/checks"
"$out/checks"
