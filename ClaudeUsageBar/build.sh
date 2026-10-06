#!/bin/zsh
# Builds ClaudeUsageBar.app from src/. Version comes from ./VERSION; STAGE and BUILD below.
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
STAGE="alpha"
BUILD="${BUILD:-1}"
APP="ClaudeUsageBar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
swiftc -O -target "$(uname -m)-apple-macos13.0" \
  src/main.swift src/Model.swift src/Usage.swift src/Forecast.swift src/Theme.swift src/Avatar.swift src/Views.swift src/Dashboard.swift \
  -o "$APP/Contents/MacOS/ClaudeUsageBar"
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
swiftc src/makeicon.swift -o build/makeicon
build/makeicon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
<key>CFBundleIdentifier</key><string>local.claudeusagebar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Claude Usage Bar</string>
<key>CFBundleDisplayName</key><string>Claude Usage Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>ClaudeUsageBarStage</key><string>$STAGE</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHumanReadableCopyright</key><string>Claude Usage Bar $VERSION $STAGE – unofficial, not affiliated with Anthropic</string>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION $STAGE, build $BUILD)"
