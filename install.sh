#!/bin/zsh
# Installs the latest Claude Usage release from GitHub into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Ol775/Claude-Usage/main/install.sh | zsh
set -e
repo="Ol775/Claude-Usage"
tmp=$(mktemp -d); trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
echo "Downloading the latest Claude Usage…"
url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | grep -o 'https://[^"]*\.dmg"' | tr -d '"' | head -1)
[ -n "$url" ] || { echo "Couldn't find a release to download. Check your internet connection."; exit 1; }
curl -fsSL -o "$tmp/Claude-Usage.dmg" "$url"
dmg="$tmp/Claude-Usage.dmg"
if sum=$(curl -fsSL "$url.sha256" 2>/dev/null) && [ -n "$sum" ]; then      # releases ship a checksum file; verify it
  [ "$(shasum -a 256 "$dmg" | cut -d' ' -f1)" = "$(echo "$sum" | cut -d' ' -f1)" ] || { echo "The download didn't match its checksum. Not installing."; exit 1; }
  echo "Checksum verified."
fi
mkdir "$tmp/mnt"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$tmp/mnt" -quiet
osascript -e 'tell application "Claude Usage" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/Claude Usage.app"
cp -R "$tmp/mnt/Claude Usage.app" /Applications/
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app" 2>/dev/null || true
open "/Applications/Claude Usage.app"
echo "✅ Installed Claude Usage $(defaults read "/Applications/Claude Usage.app/Contents/Info" CFBundleShortVersionString)"
