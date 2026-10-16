#!/bin/sh
# Exits 0 when $1 is a release version: digits separated by dots, such as 1.2.0. Anything else exits 1. A version is
# written to GITHUB_ENV and Info.plist, so a newline, a quote, or a tag suffix must never get through. Plain sh, so
# build.sh and test.sh can both run it.
version="${1-}"
case "$version" in
    [0-9]*) ;;
    *) exit 1 ;;
esac
case "$version" in
    *[!0-9.]* | *. | *..*) exit 1 ;;
esac
exit 0
