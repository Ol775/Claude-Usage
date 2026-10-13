#!/bin/zsh
# Publishes the current VERSION: builds the universal DMG, signs it with the release key, creates the GitHub release
# (DMG + .sha256 + .sig) and updates the Homebrew tap. Run after ./bump.sh, a build, and pushing the commit.
# Usage: ./release.sh [--dry-run] [--beta] ["extra note"]   – the release notes are this version's CHANGELOG entry (plus the optional note)
#   --dry-run  runs every check and builds + tests the signed DMG, but publishes nothing.
#   --beta     publishes a GitHub pre-release (only "Get beta versions" installs see it; Homebrew isn't updated). A normal release never uses it.
# Full flow, in order: ./bump.sh → ./build.sh + --selftest → commit → push → wait for green CI → ./release.sh (see ../RELEASING.md).
# Key rotation (see ../RELEASING.md): ROTATING=1 SIGNING_KEY=<old key> ./release.sh  signs with the old key a build that embeds the new one.
# The signing key (never committed, back it up!) lives at ~/.config/claude-usage/signing.key; its public half is built into the app.
set -e
cd "$(dirname "$0")"
ver=$(cat VERSION)
beta=0; dry=0; extra=""
for a in "$@"; do case "$a" in --beta) beta=1 ;; --dry-run) dry=1 ;; *) extra="$a" ;; esac; done
changes=$(awk -v v="## $ver " 'index($0, v) == 1 {on = 1; next} /^## / {on = 0} on' CHANGELOG.md | sed '/^$/d')
[ -n "$changes" ] || { echo "No CHANGELOG entry for $ver."; exit 1; }
note="$changes${extra:+

$extra}

**Install or update:** the app updates itself, or see [Install](https://github.com/Ol775/Claude-Usage#install). Every DMG is signed with the offline release key and has a SHA-256 checksum; see [how updates are verified](https://github.com/Ol775/Claude-Usage/blob/main/SECURITY.md#how-updates-are-trusted)."
tap="${TAP_DIR:-$HOME/Projects/homebrew-tap}"
key="${SIGNING_KEY:-$HOME/.config/claude-usage/signing.key}"
[ -f "$key" ] || { echo "No signing key at $key. Releases must be signed (see sign-tool.swift)."; exit 1; }
[ -z "$(git -C .. status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
sha_head=$(git rev-parse HEAD)
ci=$(gh run list --repo Ol775/Claude-Usage --workflow CI --commit "$sha_head" --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"' 2>/dev/null)
[ "$ci" = "completed success" ] || { echo "CI hasn't passed for this commit yet ($ci). Wait for it (gh run watch), then run again."; exit 1; }
last=$(grep -oE '^- \*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' ../SECURITY.md | grep -oE '[0-9.]+' | sort -V | tail -1)
unreviewed=0
for t in $(gh release list --repo Ol775/Claude-Usage --limit 50 --json tagName --jq '.[].tagName' | sed 's/^v//'); do
  [ "$t" != "$ver" ] && [ "$t" != "$last" ] && [ "$(printf '%s\n%s\n' "$last" "$t" | sort -V | tail -1)" = "$t" ] && unreviewed=$((unreviewed + 1))
done
if [ "$unreviewed" -ge 2 ] && [ "${ALLOW_UNREVIEWED:-}" != 1 ]; then
  echo "$unreviewed releases since the last security review (v$last). Review, add it to SECURITY.md, then release (ALLOW_UNREVIEWED=1 overrides)."; exit 1
fi
mkdir -p build && swiftc -O sign-tool.swift -o build/sign-tool 2>/dev/null
if [ "$(build/sign-tool public "$key")" != "$(grep -o 'publicKey = "[^"]*"' src/Updater.swift | cut -d'"' -f2)" ] && [ "${ROTATING:-}" != 1 ]; then
  echo "The signing key doesn't match the public key built into the app (set ROTATING=1 only for a key-rotation release)."; exit 1
fi
./make-dmg.sh >/dev/null 2>&1
dmg="dist/Claude-Usage-$ver.dmg"
[ "$(defaults read "$PWD/Claude Usage.app/Contents/Info" CFBundleShortVersionString)" = "$ver" ] || { echo "The built app isn't version $ver."; exit 1; }
"./Claude Usage.app/Contents/MacOS/ClaudeUsage" --selftest | tail -1 | grep -q '^OK' || { echo "Self-test failed on the release build."; exit 1; }
build/sign-tool sign "$key" "$dmg" > "$dmg.sig"                      # legacy (DMG bytes only): installs from 0.9.10-0.9.12 still need it
build/sign-tool sign-update "$key" "$dmg" "$ver" > "$dmg.sig2"      # version-bound: required by 0.9.13 and later
[ "$dry" = 1 ] && { echo "Dry run OK: v$ver would be published ($([ $beta = 1 ] && echo beta pre-release || echo normal release)), DMG and signatures verified."; exit 0; }
gh release create "v$ver" "$dmg" "$dmg.sha256" "$dmg.sig" "$dmg.sig2" --repo Ol775/Claude-Usage --title "v$ver" --notes "$note" $([ $beta = 1 ] && echo --prerelease || echo --latest)
sha=$(cut -d' ' -f1 "$dmg.sha256")
if [ -d "$tap/.git" ] && [ $beta != 1 ]; then
  git -C "$tap" pull -q --rebase origin main      # the tap also holds other apps' casks, so a push can otherwise be rejected
  sed -i '' -e "s/^  version \".*\"/  version \"$ver\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/claude-usage.rb"
  git -C "$tap" add -A && git -C "$tap" commit -q -m "claude-usage $ver" && git -C "$tap" push -q origin main
  echo "Homebrew tap updated to $ver"
fi
echo "Released v$ver"
