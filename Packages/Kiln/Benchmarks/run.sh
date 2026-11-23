#!/bin/zsh
# Builds KilnBench (release) and times Kiln on the standard inputs: Kiln's
# example apps and model replies, Shelf's fixtures, and the compute workloads.
#   Benchmarks/run.sh OUT.json [--compare BASE.json] [--runs N]
# With --compare, exits 1 when any input's warm validate median is more than
# 10% slower than in BASE (PLAN.md §1.10).
set -e
KILN=${0:A:h:h}
OUT=${1:?usage: Benchmarks/run.sh OUT.json [--compare BASE.json] [--runs N]}
shift
RUNS=21
EXTRA=()
while (( $# )); do
  case $1 in
    --runs) RUNS=$2; shift 2 ;;
    *) EXTRA+=$1; shift ;;
  esac
done
(cd "$KILN/Tools/KilnBench" && swift build -c release 2>&1 | grep -E "error:" || true)
python3 "$KILN/Tools/bench.py" "$OUT" --runs "$RUNS" --prelude "$KILN/Benchmarks/shelf-db-prelude.swift" "${EXTRA[@]}" \
  "$KILN/Examples/Apps" "$KILN/Examples/AppleIntelligence" "$KILN/Examples/Networking" \
  "$KILN/../../fixtures/apps" "$KILN/Benchmarks/Workloads"
