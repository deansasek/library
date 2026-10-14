#!/bin/zsh
# Renders the app's views to PNG files in light and dark appearance, so you can check them by eye.
# Usage: Tests/render.sh [output folder]. Without a folder, the PNGs go to a new temporary folder, which is printed.
# Needs no Xcode, window server, or screen-recording permission. It uses the same source files as test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

sources=(${(f)"$(find Sources/Library -name '*.swift' ! -name LibraryApp.swift)"})
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
folder="${1:-$(mktemp -d)}"

swiftc -swift-version 6 $sources Tests/Render/main.swift -o "$out/render"
"$out/render" "$folder"
