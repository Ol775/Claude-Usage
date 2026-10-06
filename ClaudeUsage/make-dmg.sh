#!/bin/zsh
# Builds the app and packs it into dist/Claude-Usage-<version>.dmg (drag-to-Applications installer).
set -e
cd "$(dirname "$0")"
UNIVERSAL=1 ./build.sh >/dev/null
ver=$(cat VERSION)
out="dist/Claude-Usage-$ver.dmg"
stage=$(mktemp -d)
mkdir -p dist
cp -R "Claude Usage.app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -volname "Claude Usage $ver" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out" >/dev/null
rm -rf "$stage"
(cd dist && shasum -a 256 "Claude-Usage-$ver.dmg" > "Claude-Usage-$ver.dmg.sha256")
echo "$out"
