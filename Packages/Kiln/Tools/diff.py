#!/usr/bin/env python3
"""Helpers for Tools/diff.sh.

    diff.py extract TESTS_DIR OUT_DIR
        Writes every multi-line string literal in Kiln's tests that holds a
        SwiftUI view (`View` and `body`) to OUT_DIR as its own .swift file.

    diff.py compare OUT.md EXPECTED.txt BASE_BIN NEW_BIN PRELUDE REPO INPUT…
        Runs both KilnDiff builds on each input (back to back, so clock-based
        text matches), compares the transcripts and writes OUT.md. Exits 1
        when an input differs and isn't named in EXPECTED.txt.
"""
import json, os, re, subprocess, sys, difflib

def extract(tests, out):
    n = 0
    for name in sorted(os.listdir(tests)):
        # AsyncTests checks what §1.3 adds; the engine before it is no oracle there.
        if not name.endswith(".swift") or name == "AsyncTests.swift": continue
        text = open(os.path.join(tests, name)).read()
        for i, m in enumerate(re.finditer(r'(#*)"""\n(.*?)\n([ \t]*)"""\1', text, re.S)):
            raw, body, indent = m.group(1), m.group(2), m.group(3)
            if "View" not in body or "body" not in body: continue
            lines = [l[len(indent):] if l.startswith(indent) else l.lstrip() for l in body.split("\n")]
            src = "\n".join(lines)
            if not raw:
                src = src.replace('\\"', '"').replace("\\\\", "\\")
            open(os.path.join(out, f"{name[:-6]}-{i}.swift"), "w").write(src + "\n")
            n += 1
    print(f"{n} sources from {tests}")

def run(binary, prelude, path):
    p = subprocess.run([binary, "--prelude", prelude, path], capture_output=True, text=True, timeout=120)
    lines = [l for l in p.stdout.splitlines() if l.startswith("@@KILNDIFF@@")]
    if not lines: return f"crashed (exit {p.returncode})\n" + p.stderr[-2000:]
    return json.loads(lines[0][len("@@KILNDIFF@@"):])["transcript"]

def label(path, repo):
    rel = os.path.relpath(os.path.abspath(path), repo)
    return rel if not rel.startswith("..") else "tests/" + os.path.basename(path)

def compare(out, expected_path, base_bin, new_bin, prelude, repo, inputs):
    expected = {}
    if os.path.exists(expected_path):
        for line in open(expected_path):
            line = line.strip()
            if line and not line.startswith("#"):
                name, _, why = line.partition(" ")
                expected[name] = why.strip()
    rows, unexpected = [], []
    for path in inputs:
        name = label(path, repo)
        a, b = run(base_bin, prelude, path), run(new_bin, prelude, path)
        if a != b:  # Clock text can tick over between the two runs: once more.
            a2, b2 = run(base_bin, prelude, path), run(new_bin, prelude, path)
            if a2 == b2: a, b = a2, b2
        same = a == b
        diff = [] if same else list(difflib.unified_diff(a.splitlines(), b.splitlines(), "before", "after", lineterm="", n=1))
        steps = a.count("\n== ") + 1
        status = "identical" if same else ("expected" if name in expected else "DIFFERENT")
        if status == "DIFFERENT": unexpected.append(name)
        rows.append((name, status, len(a.splitlines()), steps, diff))
        print(f"{name:60} {status}")
    with open(out, "w") as f:
        same = sum(1 for r in rows if r[1] == "identical")
        exp = sum(1 for r in rows if r[1] == "expected")
        f.write("# Differential check\n\n")
        f.write("Every input run on the engine before §1.3 (`cc388b1`) and on this one, comparing their transcripts: "
                "the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again "
                "after each scripted action (`onAppear` and `.task` first, then each button and tap). "
                "`Tools/diff.sh` writes this file.\n\n")
        f.write(f"**{len(rows)} inputs: {same} identical, {exp} different as expected, {len(unexpected)} different otherwise.**\n\n")
        f.write("| Input | Transcript lines | Steps | Result |\n|---|---:|---:|---|\n")
        for name, status, n, steps, _ in rows:
            note = f" ({expected[name]})" if status == "expected" else ""
            f.write(f"| {name} | {n} | {steps} | {status}{note} |\n")
        for name, status, _, _, diff in rows:
            if status == "identical": continue
            f.write(f"\n## {name}\n\n```diff\n" + "\n".join(diff[:120]) + ("\n…" if len(diff) > 120 else "") + "\n```\n")
    print(f"{len(rows)} inputs, {len(unexpected)} unexpectedly different; wrote {out}")
    return 1 if unexpected else 0

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "extract": extract(sys.argv[2], sys.argv[3])
    elif cmd == "compare": sys.exit(compare(*sys.argv[2:8], sys.argv[8:]))
