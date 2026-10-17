#!/bin/sh
# Prints the version build.sh stamps and update.sh reports, so both read it from one place and cannot drift:
# $VERSION, else the VERSION file a release zip carries, else the nearest tag reachable from HEAD (without its v
# prefix). Exits 1 when nothing resolves: a source build must not claim to be older than the latest release, or the
# update check would offer that release every time. Plain sh, so build.sh, update.sh, and test.sh can all run it.
# Reads the git tag from the current directory, so it is run from the repository root.
set -eu
version="${VERSION:-}"
if [ -z "$version" ] && [ -r VERSION ]; then
    version="$(cat VERSION)"
fi
if [ -z "$version" ]; then
    tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    version="${tag#v}"
fi
if [ -z "$version" ]; then
    echo "No version tag is reachable. Run git fetch --tags, or set VERSION." >&2
    exit 1
fi
printf '%s\n' "$version"
