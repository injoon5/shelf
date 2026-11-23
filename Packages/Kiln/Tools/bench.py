#!/usr/bin/env python3
"""Run KilnBench on each input with a time limit; print one summary line per input
and write the rows to the JSON path given as the first argument.

    bench.py OUT.json [--runs N] [--prelude FILE] [--compare BASE.json] INPUT…

An INPUT is a .swift or .md file, or a directory of them. With --compare, each
input's validate time (the minimum per call over the samples, the steadiest
number) is shown against BASE's, and the script exits 1 when any is more than
10% slower (PLAN.md §1.10)."""
import json, subprocess, sys, os

args = sys.argv[1:]
out = args.pop(0)
runs, prelude, compare, inputs = 1, None, None, []
while args:
    a = args.pop(0)
    if a == "--runs": runs = int(args.pop(0))
    elif a == "--prelude": prelude = args.pop(0)
    elif a == "--compare": compare = args.pop(0)
    elif os.path.isdir(a):
        inputs += sorted(os.path.join(a, f) for f in os.listdir(a) if f.endswith((".swift", ".md")) and f != "README.md")
    else: inputs.append(a)

bench = os.path.join(os.path.dirname(os.path.abspath(__file__)), "KilnBench/.build/release/KilnBench")
base = {}
if compare:
    for r in json.load(open(compare)).get("rows", []):
        base[r.get("input", r["file"])] = r

def label(path):
    """The input's directory and name, so two folders' state.swift don't collide."""
    return os.path.join(os.path.basename(os.path.dirname(os.path.abspath(path))), os.path.basename(path))

def bench_one(path):
    cmd = [bench, "--runs", str(runs)] + (["--prelude", prelude] if prelude else []) + [path]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60 + 3 * runs)
        lines = [l for l in p.stdout.splitlines() if l.startswith("@@KILNBENCH@@")]
        return json.loads(lines[0][len("@@KILNBENCH@@"):]) if lines else {"file": os.path.basename(path), "valid": False, "errors": [f"crashed (exit {p.returncode})"]}
    except subprocess.TimeoutExpired:
        return {"file": os.path.basename(path), "valid": False, "hung": True, "errors": ["hung: no result in time"]}

def slower(row, name):
    b = base.get(name, {}).get("validateMinMs")
    return bool(b and row.get("validateMinMs") and row["validateMinMs"] / b > 1.10)

rows, regressions = [], []
for path in inputs:
    name = label(path)
    row = bench_one(path)
    # A busy machine slows one input now and then. Before calling it a
    # regression, time it twice more and keep the fastest.
    for _ in range(2):
        if not slower(row, name): break
        again = bench_one(path)
        if again.get("validateMinMs", float("inf")) < row.get("validateMinMs", float("inf")): row = again
    row["input"] = name
    rows.append(row)
    status = "PASS" if row.get("valid") else ("HUNG" if row.get("hung") else "FAIL")
    timing = f"run {row.get('runMinMs', '-'):>7} ms  validate {row.get('validateMinMs', '-'):>8} ms (min)  {row.get('validateMedianMs', '-'):>8} (median)"
    delta = ""
    if name in base and row.get("validateMinMs") and base[name].get("validateMinMs"):
        ratio = row["validateMinMs"] / base[name]["validateMinMs"]
        delta = f"  {100 * (ratio - 1):+6.1f}%"
        if ratio > 1.10: regressions.append(name); delta += "  SLOWER"
    print(f"{name:40} {status}  {timing}{delta}")
    for e in row.get("errors", [])[:3]: print("     ERR ", e[:200])
    for w in row.get("warnings", [])[:3]: print("     WARN", w[:170])

total = sum(r.get("validateMinMs", 0) for r in rows)
print(f"{'total (validate minimums)':40}       {total:.2f} ms")
json.dump({"runs": runs, "prelude": os.path.basename(prelude) if prelude else None, "rows": rows},
          open(out, "w"), indent=1, sort_keys=True)
if regressions:
    print("More than 10% slower: " + ", ".join(regressions))
    sys.exit(1)
