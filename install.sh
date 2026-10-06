#!/bin/zsh
# Installs the latest Claude Usage release from GitHub into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Ol775/Claude-Usage/main/install.sh | zsh
set -e
repo="Ol775/Claude-Usage"
tmp=$(mktemp -d); trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
echo "Downloading the latest Claude Usage…"
url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | grep -o 'https://[^"]*\.dmg' | head -1)
[ -n "$url" ] || { echo "Couldn't find a release to download. Check your internet connection."; exit 1; }
curl -fsSL -o "$tmp/Claude-Usage.dmg" "$url"
dmg=$(echo "$tmp"/*.dmg)
mkdir "$tmp/mnt"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$tmp/mnt" -quiet
osascript -e 'tell application "Claude Usage" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/Claude Usage.app"
cp -R "$tmp/mnt/Claude Usage.app" /Applications/
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app" 2>/dev/null || true
open "/Applications/Claude Usage.app"
echo "✅ Installed Claude Usage $(defaults read "/Applications/Claude Usage.app/Contents/Info" CFBundleShortVersionString)"
