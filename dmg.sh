#!/usr/bin/env bash
# Build TabDock.app and package it as a drag-to-Applications disk image.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.0.1}"
export VERSION
./build.sh

STAGE=build/dmg
DMG="build/TabDock-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/TabDock.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname TabDock -srcfolder "$STAGE" -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "Built $DMG"
