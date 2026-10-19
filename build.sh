#!/usr/bin/env bash
# Build TabDock.app with swiftc (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.0.1}"
APP=build/TabDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Universal binary so the same bundle runs on Apple silicon and Intel Macs.
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos14.0" \
    -o "build/TabDock-$arch" \
    Sources/*.swift
done
lipo -create build/TabDock-arm64 build/TabDock-x86_64 -output "$APP/Contents/MacOS/TabDock"
rm build/TabDock-arm64 build/TabDock-x86_64

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.cuonghx.tabdock</string>
  <key>CFBundleName</key><string>TabDock</string>
  <key>CFBundleExecutable</key><string>TabDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
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
