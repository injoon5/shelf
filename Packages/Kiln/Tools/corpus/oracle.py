#!/usr/bin/env python3
"""The corpus's oracle: what compiled Swift prints for each entry.

Compiles every entry of Tests/Corpus/*.corpus (KilnCorpus.swift has the format)
as its own program with swiftc on this Mac, runs it with the corpus's time
zone and locale, and compares what it prints with the entry's `=>` lines.

    Tools/corpus/oracle.py                 # report entries whose value differs
    Tools/corpus/oracle.py --write         # write compiled Swift's values into the files
    Tools/corpus/oracle.py --write Dates   # only entries whose id or section has "Dates"

Entries marked [ios] use UIKit, which the Mac doesn't have: their values are
written by hand. Builds are cached by content in $TMPDIR/kiln-corpus-oracle.
"""
import concurrent.futures, hashlib, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.normpath(os.path.join(HERE, "..", "..", "Tests", "Corpus"))
CACHE = os.path.join(os.environ.get("TMPDIR", tempfile.gettempdir()), "kiln-corpus-oracle")
IMPORTS = "import SwiftUI\nimport Foundation\nimport Combine\nimport CryptoKit\nimport OSLog\n\n"
TZ = "America/New_York"


def parse(path):
    """Entries as dicts, with where their expected lines are in the file."""
    lines = open(path, encoding="utf-8").read().split("\n")
    out, section, i = [], "", 0
    while i < len(lines):
        raw = lines[i]
        t = raw.strip()
        i += 1
        if not t or (t.startswith("#") and not t.startswith("##")):
            continue
        if t.startswith("##"):
            section = t[2:].strip()
            continue
        if " ::" not in raw:
            continue
        head, rest = raw.split(" ::", 1)
        flags = set(re.findall(r"\[(gap|ios)\]", head))
        ident = re.sub(r"\s*\[(gap|ios)\]", "", head).strip()
        rest = rest.strip()
        start = i - 1
        expected = []
        if not rest:
            body = []
            while i < len(lines) and (lines[i].startswith("    ") or not lines[i].strip()) and not lines[i].startswith("=>"):
                body.append(lines[i][4:])
                i += 1
            while body and not body[-1].strip():
                body.pop()
            code = "\n".join(body)
            oneline = False
        else:
            m = re.search(r" =>( (.*))?$", rest)
            if m:
                expected.append(m.group(2) or "")
                rest = rest[: m.start()]
            code = rest if "print(" in rest else f"print({rest})"
            oneline = True
        exp_start = i
        while i < len(lines) and lines[i].startswith("=>"):
            e = lines[i][2:]
            expected.append(e[1:] if e.startswith(" ") else e)
            i += 1
        out.append(dict(id=ident, section=section, flags=flags, code=code, expected=expected, start=start,
                        exp_start=exp_start, exp_end=i, oneline=oneline, rest=rest))
    prelude = next((e for e in out if e["id"] == "prelude"), None)
    out = [e for e in out if e["id"] != "prelude"]
    if prelude:
        for e in out:
            e["code"] = prelude["code"] + "\n" + e["code"]
    return lines, out


def run(code):
    """What the code prints, compiled. Cached by content."""
    os.makedirs(CACHE, exist_ok=True)
    src = IMPORTS + code + "\n"
    key = hashlib.sha1((src + TZ).encode()).hexdigest()[:16]
    out_path = os.path.join(CACHE, key + ".out")
    if os.path.exists(out_path):
        return open(out_path, encoding="utf-8").read().split("\n")[:-1]
    d = tempfile.mkdtemp(dir=CACHE)
    with open(os.path.join(d, "main.swift"), "w", encoding="utf-8") as f:
        f.write(src)
    b = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-suppress-warnings", "-Onone", "-enable-bare-slash-regex",
                        "main.swift", "-o", "bin"], cwd=d, capture_output=True, text=True)
    if b.returncode != 0:
        err = [l for l in b.stderr.split("\n") if "error:" in l][:2]
        return ["COMPILE ERROR: " + " | ".join(e.split("error:", 1)[1].strip() for e in err)]
    env = dict(os.environ, TZ=TZ)
    r = subprocess.run(["./bin", "-AppleLocale", "en_US", "-AppleLanguages", "(en)"], cwd=d, capture_output=True, text=True,
                       env=env, timeout=60)
    text = r.stdout
    if r.returncode != 0:
        text += f"CRASHED ({r.returncode})\n"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text if text.endswith("\n") or not text else text + "\n")
    subprocess.run(["rm", "-rf", d])
    return text.split("\n")[:-1] if text else []


def main():
    args = sys.argv[1:]
    write = "--write" in args
    filters = [a for a in args if not a.startswith("--")]
    files = sorted(f for f in os.listdir(CORPUS) if f.endswith(".corpus"))
    for name in files:
        path = os.path.join(CORPUS, name)
        lines, entries = parse(path)
        todo = [e for e in entries if "ios" not in e["flags"] and (not filters or any(f in e["id"] or f in e["section"] for f in filters))]
        with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            results = list(pool.map(lambda e: run(e["code"]), todo))
        edits = []
        for e, got in zip(todo, results):
            if got == e["expected"]:
                continue
            print(f"{name}:{e['start'] + 1} {e['id']}\n   file: {' ⏎ '.join(e['expected'])}\n  swift: {' ⏎ '.join(got)}")
            if any(g.startswith("COMPILE ERROR") for g in got):
                continue
            edits.append((e, got))
        if write and edits:
            for e, got in sorted(edits, key=lambda x: -x[0]["start"]):
                if e["oneline"] and len(got) == 1 and e["exp_end"] == e["exp_start"]:
                    head = lines[e["start"]].split(" ::", 1)[0]
                    lines[e["start"]] = f"{head} :: {e['rest']} => {got[0]}"
                elif e["oneline"]:
                    head = lines[e["start"]].split(" ::", 1)[0]
                    lines[e["start"]] = f"{head} :: {e['rest']}"
                    lines[e["start"] + 1:e["exp_end"]] = ["=> " + g for g in got]
                else:
                    lines[e["exp_start"]:e["exp_end"]] = ["=> " + g for g in got]
            open(path, "w", encoding="utf-8").write("\n".join(lines))
            print(f"wrote {len(edits)} values into {name}")


if __name__ == "__main__":
    main()
