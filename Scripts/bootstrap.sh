#!/bin/sh
# Generates Shelf.xcodeproj from project.yml. Run it once after cloning, and
# again after changing project.yml. Kiln is in the repo (Packages/Kiln), so
# nothing is fetched.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
echo "Shelf.xcodeproj generated."
