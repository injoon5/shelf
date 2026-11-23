#!/bin/sh
# Regenerates Packages/Kiln/COVERAGE.md and coverage.json from this Mac's iOS SDK
# (PLAN.md §1.9). Run it after each round and after each Xcode update.
#
#   Packages/Kiln/Tools/coverage.sh              # write the report
#   Packages/Kiln/Tools/coverage.sh --dry-run    # print the summary only
#   Packages/Kiln/Tools/coverage.sh --manifest path/to/kiln-manifest.json
#
# Until §1.4's registry writes Packages/Kiln/kiln-manifest.json, this also
# rebuilds Tools/coverage/kiln-manifest.interim.json from the engine's switches.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
exec swift run --quiet --package-path "$here/coverage" coverage "$@"
