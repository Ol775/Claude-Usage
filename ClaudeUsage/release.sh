#!/bin/zsh
# Publishes the current VERSION: builds the universal DMG, signs it with the release key, creates the GitHub release
# (DMG + .sha256 + .sig) and updates the Homebrew tap. Run after ./bump.sh, a build, and pushing the commit.
# Usage: ./release.sh "short release note"
# The signing key (never committed, back it up!) lives at ~/.config/claude-usage/signing.key; its public half is built into the app.
set -e
cd "$(dirname "$0")"
note="${1:?usage: ./release.sh \"short release note\"}"
ver=$(cat VERSION)
tap="${TAP_DIR:-$HOME/Projects/homebrew-tap}"
key="${SIGNING_KEY:-$HOME/.config/claude-usage/signing.key}"
[ -f "$key" ] || { echo "No signing key at $key. Releases must be signed (see sign-tool.swift)."; exit 1; }
[ -z "$(git -C .. status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
mkdir -p build && swiftc -O sign-tool.swift -o build/sign-tool 2>/dev/null
[ "$(build/sign-tool public "$key")" = "$(grep -o 'publicKey = "[^"]*"' src/Updater.swift | cut -d'"' -f2)" ] || { echo "The signing key doesn't match the public key built into the app."; exit 1; }
./make-dmg.sh >/dev/null 2>&1
dmg="dist/Claude-Usage-$ver.dmg"
build/sign-tool sign "$key" "$dmg" > "$dmg.sig"                      # legacy (DMG bytes only): installs from 0.9.10-0.9.12 still need it
build/sign-tool sign-update "$key" "$dmg" "$ver" > "$dmg.sig2"      # version-bound: required by 0.9.13 and later
gh release create "v$ver" "$dmg" "$dmg.sha256" "$dmg.sig" "$dmg.sig2" --repo Ol775/Claude-Usage --title "v$ver" --notes "$note" --latest
sha=$(cut -d' ' -f1 "$dmg.sha256")
if [ -d "$tap/.git" ]; then
  sed -i '' -e "s/^  version \".*\"/  version \"$ver\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/claude-usage.rb"
  git -C "$tap" add -A && git -C "$tap" commit -q -m "claude-usage $ver" && git -C "$tap" push -q origin main
  echo "Homebrew tap updated to $ver"
fi
echo "Released v$ver"
