#!/bin/sh
# Writes Packages/Kiln/kiln-manifest.json from the bridge registry (PLAN.md
# §1.4, Docs/manifest.md), then the coverage report that reads it.
#   Packages/Kiln/Tools/manifest.sh
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
KILN_WRITE_MANIFEST=1 swift test --filter RegistryTests/testManifestIsCurrent >/dev/null
echo "wrote $here/kiln-manifest.json"
