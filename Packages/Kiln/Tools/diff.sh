#!/bin/zsh
# The differential check (PLAN.md §1.3): runs every input on the engine at
# BASE (default: cc388b1, the one engine before §1.3) and on this checkout,
# and compares their transcripts (Kiln.transcript: the view tree, console,
# errors with lines, and state after each scripted action).
#   Tools/diff.sh [OUT.md] [--base REF]
# Writes OUT.md (default Benchmarks/differential.md) and exits 1 when an
# input differs in a way not listed as expected in Tools/diff-expected.txt.
set -e
KILN=${0:A:h:h}
REPO=$(git -C "$KILN" rev-parse --show-toplevel)
OUT="$KILN/Benchmarks/differential.md"
BASE=cc388b1
while (( $# )); do
  case $1 in
    --base) BASE=$2; shift 2 ;;
    *) OUT=${1:A}; shift ;;
  esac
done
WORK=${TMPDIR:-/tmp}/kilndiff
rm -rf "$WORK/Kiln/Sources" "$WORK/inputs"
mkdir -p "$WORK/Kiln" "$WORK/inputs/tests"

echo "== baseline engine at $BASE"
git -C "$REPO" archive "$BASE" Packages/Kiln/Package.swift Packages/Kiln/Sources | tar -x -C "$WORK/Kiln" --strip-components 2
cp "$KILN/Sources/Kiln/Engine/KETranscript.swift" "$WORK/Kiln/Sources/Kiln/Engine/"
cp "$KILN/Tools/KilnDiff/BaselineShim.swift" "$WORK/Kiln/Sources/Kiln/Engine/"
mkdir -p "$WORK/Kiln/Tools/KilnDiff/Sources/KilnDiff"
cp "$KILN/Tools/KilnDiff/Package.swift" "$WORK/Kiln/Tools/KilnDiff/"
cp "$KILN/Tools/KilnDiff/Sources/KilnDiff/main.swift" "$WORK/Kiln/Tools/KilnDiff/Sources/KilnDiff/"
(cd "$WORK/Kiln/Tools/KilnDiff" && swift build -c release 2>&1 | grep -E "error:" || true)

echo "== this engine"
(cd "$KILN/Tools/KilnDiff" && swift build -c release 2>&1 | grep -E "error:" || true)

echo "== inputs"
python3 "$KILN/Tools/diff.py" extract "$KILN/Tests/KilnTests" "$WORK/inputs/tests"
INPUTS=("$KILN"/Examples/Apps/*.swift "$KILN"/Examples/AppleIntelligence/*.md "$KILN"/Examples/Networking/*.swift
        "$KILN"/Examples/LibraryApp.swift "$REPO"/fixtures/apps/*.swift "$KILN"/Benchmarks/Workloads/*.swift
        "$WORK"/inputs/tests/*.swift)
PRELUDE="$KILN/Benchmarks/shelf-db-prelude.swift"
python3 "$KILN/Tools/diff.py" compare "$OUT" "$KILN/Tools/diff-expected.txt" \
  "$WORK/Kiln/Tools/KilnDiff/.build/release/KilnDiff" "$KILN/Tools/KilnDiff/.build/release/KilnDiff" \
  "$PRELUDE" "$REPO" "${INPUTS[@]}"
