#!/bin/sh
# Builds Shelf for a simulator and installs it there. Launching is left to
# whoever is driving the simulator. The build is signed (ad hoc, no team
# needed): an unsigned app can't use the Keychain, where the token lives.
#   Scripts/run.sh [simulator-udid]
set -eu
cd "$(dirname "$0")/.."
UDID="${1:-booted}"
xcodebuild build -project Shelf.xcodeproj -scheme Shelf \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES 2>&1 \
  | grep -E "error|warning: |\*\* " | grep -v "Packages/Kiln\|appintentsmetadata" | sort -u || true
xcrun simctl install "$UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/Shelf.app
