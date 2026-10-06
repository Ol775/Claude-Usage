#!/bin/zsh
# Pulls the latest Claude Usage from GitHub, rebuilds it, installs it to /Applications and relaunches it.
set -e
cd "$(dirname "$0")"
git pull --ff-only
cd ClaudeUsage
./build.sh
osascript -e 'tell application "Claude Usage" to quit' >/dev/null 2>&1 || true
sleep 1.5
rm -rf "/Applications/Claude Usage.app"
cp -R "Claude Usage.app" "/Applications/Claude Usage.app"
open "/Applications/Claude Usage.app"
echo "✅ Updated to $(cat VERSION)"
