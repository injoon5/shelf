#!/bin/zsh
# One pass of the Kiln improvement loop.
#   Tools/iterate.sh "<short label>" "<what changed>"
# Runs the engine bench, then the Kiln Lab UI tests (each example app natively
# and in Kiln, plus Apple Intelligence's replies in Kiln), and writes
# ~/Desktop/Kiln Iterations/NN - <label>/ with side-by-side screens and a report.
set -e
KILN=${0:A:h:h}
LABEL=${1:-run}
CHANGED=${2:-}
ROOT="$HOME/Desktop/Kiln Iterations"
mkdir -p "$ROOT"
N=$(( $(ls -d "$ROOT"/[0-9][0-9]* 2>/dev/null | wc -l) + 1 ))
OUT="$ROOT/$(printf %02d $N) - $LABEL"
mkdir -p "$OUT"
# Lab/.sim-udid pins a simulator; otherwise the first available iPhone.
SIM=$(cat "$KILN/Lab/.sim-udid" 2>/dev/null || xcrun simctl list devices available | grep -m1 -E "iPhone" | grep -oE "[0-9A-F-]{36}")
WORK=$(mktemp -d -t kilniter)

echo "== bench"
# Against the latest recorded step (Benchmarks/README.md): an input more than
# 10% slower is marked SLOWER.
"$KILN/Benchmarks/run.sh" "$OUT/bench.json" --compare "$KILN/Benchmarks/after-3c-round2c.json" | tee "$OUT/bench.txt"

echo "== lab"
cd "$KILN/Lab"
python3 gen_native.py >/dev/null
xcodegen generate --quiet
xcrun simctl boot "$SIM" 2>/dev/null || true
# KILN_DERIVED_DATA shares a DerivedData folder with other builds (a worktree's build/DerivedData).
DERIVED=()
[ -n "${KILN_DERIVED_DATA:-}" ] && DERIVED=(-derivedDataPath "$KILN_DERIVED_DATA")
xcodebuild test -project KilnLab.xcodeproj -scheme KilnLab -destination "id=$SIM" "${DERIVED[@]}" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 150 \
  -resultBundlePath "$WORK/run.xcresult" > "$WORK/test.log" 2>&1 || true
grep -E "Test Case .*(passed|failed)|error:|BUILD FAILED" "$WORK/test.log" | sed 's/^.*Test Case/Test Case/' | cut -c1-160 > "$OUT/tests.txt" || true
cat "$OUT/tests.txt"

echo "== report"
python3 "$KILN/Lab/report.py" "$WORK/run.xcresult" "$OUT/bench.json" "$OUT" "$LABEL" "$CHANGED" >/dev/null
echo "$OUT"
