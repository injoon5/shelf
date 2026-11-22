#!/bin/sh
# Fetches Kiln at the pinned tag into Vendor/Kiln, applies Shelf's patch to it,
# and generates the Xcode project. Run it once after cloning, and again after
# changing KILN_TAG or the patch.
#
# The patch exists because Kiln 0.2.1 cannot write JSON: `JSONEncoder().encode`
# is missing, `[Todo].self` fails, and a decoded `var id = UUID()` comes back as
# a String. Apps need all three to save anything through `DB`. When a Kiln
# release includes them, delete the patch and pin the package in project.yml.
set -eu

KILN_TAG=0.2.1
cd "$(dirname "$0")/.."

if [ ! -f "Vendor/Kiln/.shelf-$KILN_TAG" ] || [ "Vendor/kiln-$KILN_TAG.patch" -nt "Vendor/Kiln/.shelf-$KILN_TAG" ]; then
  rm -rf Vendor/Kiln
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$KILN_TAG" https://github.com/haplollc/Kiln Vendor/Kiln
  rm -rf Vendor/Kiln/.git
  patch --quiet -p1 -d Vendor/Kiln < "Vendor/kiln-$KILN_TAG.patch"
  touch "Vendor/Kiln/.shelf-$KILN_TAG"
  echo "Kiln $KILN_TAG fetched and patched."
fi

xcodegen generate --quiet
echo "Shelf.xcodeproj generated."
