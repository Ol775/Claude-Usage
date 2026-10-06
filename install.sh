#!/bin/zsh
# Installs the latest Claude Usage release from GitHub into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Ol775/Claude-Usage/main/install.sh | zsh
set -e
repo="Ol775/Claude-Usage"
tmp=$(mktemp -d); trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT
echo "Downloading the latest Claude Usage…"
url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*: *"//; s/"$//')
case "$url" in "https://github.com/$repo/releases/download/"*.dmg) ;; *) echo "Couldn't find a release to download. Check your internet connection."; exit 1 ;; esac
dmg="$tmp/Claude-Usage.dmg"
curl -fsSL -o "$dmg" "$url"
# The checksum is required: if it can't be fetched or doesn't match, nothing is installed.
sum=$(curl -fsSL "$url.sha256" | cut -d' ' -f1)
[ -n "$sum" ] && [ "$(shasum -a 256 "$dmg" | cut -d' ' -f1)" = "$sum" ] || { echo "The download couldn't be verified against its checksum. Not installing."; exit 1; }
echo "Checksum verified."
mkdir "$tmp/mnt"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$tmp/mnt" -quiet
cp -R "$tmp/mnt/Claude Usage.app" "$tmp/new.app"                       # copy out first, so a failure leaves your current app alone
[ "$(defaults read "$tmp/new.app/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "local.claudeusage" ] || { echo "That download isn't Claude Usage. Not installing."; exit 1; }
codesign --verify --deep --strict "$tmp/new.app" || { echo "The app's signature is damaged. Not installing."; exit 1; }
osascript -e 'tell application "Claude Usage" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/Claude Usage.app"
mv "$tmp/new.app" "/Applications/Claude Usage.app"
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app" 2>/dev/null || true
open "/Applications/Claude Usage.app"
echo "✅ Installed Claude Usage $(defaults read "/Applications/Claude Usage.app/Contents/Info" CFBundleShortVersionString)"
