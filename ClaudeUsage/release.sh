#!/bin/zsh
# Publishes the current VERSION: builds the DMG + checksum, creates the GitHub release, and updates the Homebrew tap.
# Run after ./bump.sh, a build, and pushing the commit. Usage: ./release.sh "short release note"
set -e
cd "$(dirname "$0")"
note="${1:?usage: ./release.sh \"short release note\"}"
ver=$(cat VERSION)
tap="${TAP_DIR:-$HOME/Projects/homebrew-tap}"
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
./make-dmg.sh >/dev/null 2>&1
gh release create "v$ver" "dist/Claude-Usage-$ver.dmg" "dist/Claude-Usage-$ver.dmg.sha256" --repo Ol775/Claude-Usage --title "v$ver" --notes "$note" --latest
sha=$(cut -d' ' -f1 "dist/Claude-Usage-$ver.dmg.sha256")
if [ -d "$tap/.git" ]; then
  sed -i '' -e "s/^  version \".*\"/  version \"$ver\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/claude-usage.rb"
  git -C "$tap" add -A && git -C "$tap" commit -q -m "claude-usage $ver" && git -C "$tap" push -q origin main
  echo "Homebrew tap updated to $ver"
fi
echo "Released v$ver"
