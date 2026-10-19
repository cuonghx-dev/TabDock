#!/usr/bin/env bash
# Build TabDock.app with swiftc (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/TabDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/TabDock" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.cuonghx.tabdock</string>
  <key>CFBundleName</key><string>TabDock</string>
  <key>CFBundleExecutable</key><string>TabDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>TabDock reads open tab URLs in Google Chrome and Safari to show which web apps are running, and switches to or closes their tabs.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
