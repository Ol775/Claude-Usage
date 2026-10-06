#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="ClaudeUsageBar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O src/main.swift -o "$APP/Contents/MacOS/ClaudeUsageBar"
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
swiftc src/makeicon.swift -o build/makeicon
build/makeicon build/AppIcon.iconset
mkdir -p "$APP/Contents/Resources"
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
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHumanReadableCopyright</key><string>Claude Usage Bar</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP"
