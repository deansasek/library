#!/bin/zsh
# Builds Library and installs it in /Applications, replacing the old copy. Your data lives in ~/.library,
# apart from the app, so an update never touches it.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# Quit the running app and wait for it to exit.
pkill -x Library || true
while pgrep -x Library >/dev/null; do sleep 0.2; done

rm -rf /Applications/Library.app
cp -R build/Library.app /Applications/Library.app
open /Applications/Library.app
# Remember this clone, so Check for Updates can run ./update.sh here. The release zip has no update.sh, and the app
# then sends the user to the release page instead. Written only after the install succeeds.
defaults write com.deansasek.library sourcePath "$PWD"
echo "Installed /Applications/Library.app"
