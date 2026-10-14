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
echo "Installed /Applications/Library.app"
