#!/bin/zsh
# Compiles the checks in Tests/ together with the app's source, except the file that starts the app, and runs them.
# Tests/Bench also prints timings for a 5,000-item library. The timings never fail the run.
# They use private pasteboards and temporary files, so they never touch your clipboard or your library.
set -euo pipefail
cd "$(dirname "$0")"

sources=(${(f)"$(find Sources/Library -name '*.swift' ! -name LibraryApp.swift)"})
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -swift-version 6 -O $sources Tests/Checks/main.swift Tests/Bench/Bench.swift -o "$out/checks"
"$out/checks"
