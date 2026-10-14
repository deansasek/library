#!/bin/zsh
# Updates this clone of Library from origin/main, then runs ./install.sh. It never resets, rebases, or force-pushes:
# it refuses to run with uncommitted changes or when main is not checked out, and it only fast-forwards.
# DRY_RUN=1 ./update.sh prints the commands it would run. The read-only checks still run, nothing is fetched, pulled,
# or installed.
set -euo pipefail
cd "$(dirname "$0")"

dry_run="${DRY_RUN:-}"

# Runs a command that changes something, or prints it in dry-run mode.
change() {
    if [[ -n "$dry_run" ]]; then
        print -r -- "+ $*"
    else
        "$@"
    fi
}

# The version of the checked-out code: its latest tag (the nearest one reachable from HEAD), or the default
# CFBundleShortVersionString in build.sh when there is no tag.
version() {
    if tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
        print -r -- "$tag"
    else
        sed -n 's/.*CFBundleShortVersionString<\/key><string>\${VERSION:-\([^}]*\)}<.*/\1/p' build.sh
    fi
}

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != main ]]; then
    print -u2 "update.sh: you are on $branch. Check out main, then run this again."
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "update.sh: the working tree has uncommitted changes. Commit or stash them, then run this again."
    git status --short >&2
    exit 1
fi

before="$(version)"
print "Version before: ${before:-unknown}"

change git fetch origin
change git pull --ff-only origin main || {
    print -u2 "update.sh: main cannot be fast-forwarded to origin/main, so nothing was installed. Resolve it by hand."
    exit 1
}

after="$(version)"
print "Version after: ${after:-unknown}"
if [[ -n "$dry_run" ]]; then
    print "(dry run: the version after is the current one, because nothing was pulled)"
fi

change ./install.sh
