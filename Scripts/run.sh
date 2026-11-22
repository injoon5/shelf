#!/bin/sh
# Builds Shelf for a simulator and installs it there. Launching is left to
# whoever is driving the simulator.
#   Scripts/run.sh [simulator-udid]
set -eu
cd "$(dirname "$0")/.."
UDID="${1:-booted}"
xcodebuild build -project Shelf.xcodeproj -scheme Shelf \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES 2>&1 \
  | grep -E "error|warning: |\*\* " | grep -v "Vendor/Kiln\|appintentsmetadata" | sort -u || true
xcrun simctl install "$UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/Shelf.app
