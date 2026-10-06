#!/bin/zsh
# Builds "Claude Usage.app" from src/. Version comes from ./VERSION; STAGE and BUILD below.
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
STAGE="alpha"
# build number = commit count (rises with every commit); source downloads have no .git, so they use the BUILD_NUMBER file bump.sh writes
BUILD="${BUILD:-$( [ -d ../.git ] && git rev-list --count HEAD 2>/dev/null || cat BUILD_NUMBER 2>/dev/null || echo 1 )}"
APP="Claude Usage.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
swiftc -O -target "$(uname -m)-apple-macos13.0" \
  src/main.swift src/Model.swift src/Usage.swift src/Forecast.swift src/Theme.swift src/Avatar.swift src/BotArt.swift src/Views.swift src/Toast.swift src/Activity.swift src/MenuBar.swift src/Changelog.swift src/Updater.swift src/Dashboard.swift src/Reports.swift src/Insights.swift \
  -o "$APP/Contents/MacOS/ClaudeUsage"
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
mkdir -p build/iconsrc && cp src/makeicon.swift build/iconsrc/main.swift
swiftc build/iconsrc/main.swift src/BotArt.swift -o build/makeicon
CUSTOM=""; [ -f assets/bot.png ] && CUSTOM="assets/bot.png" && cp assets/bot.png "$APP/Contents/Resources/Bot.png"
build/makeicon build/AppIcon.iconset $CUSTOM
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"          # shown in Settings → About
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeUsage</string>
<key>CFBundleIdentifier</key><string>local.claudeusage</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Claude Usage</string>
<key>CFBundleDisplayName</key><string>Claude Usage</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>ClaudeUsageStage</key><string>$STAGE</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHumanReadableCopyright</key><string>Claude Usage $VERSION $STAGE – unofficial, not affiliated with Anthropic</string>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION $STAGE, build $BUILD)"
