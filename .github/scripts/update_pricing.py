#!/usr/bin/env python3
"""Rebuilds ClaudeUsage/pricing.json from Anthropic's published pricing table (run daily by .github/workflows/pricing.yml).
The app fetches that file once a day, so price changes and new models reach every install without a release.
Refuses to write anything that looks wrong, so a changed page can't corrupt prices (the app validates the file again)."""
import json, re, sys, urllib.request, datetime, pathlib

URL = "https://platform.claude.com/docs/en/about-claude/pricing.md"
OUT = pathlib.Path(__file__).resolve().parents[2] / "ClaudeUsage" / "pricing.json"

def prefix(name):
    """'Claude Opus 5.5' -> 'claude-opus-5-5'; models before version 4 are named 'claude-3-5-haiku'."""
    m = re.match(r"Claude (\w+) (\d+(?:\.\d+)?)", name)
    if not m: return None
    fam, ver = m.group(1).lower(), m.group(2).replace(".", "-")
    return f"claude-{ver}-{fam}" if int(ver.split("-")[0]) < 4 else f"claude-{fam}-{ver}"

def money(cell):
    m = re.match(r"\$([\d.]+)\s*/\s*MTok", cell.strip())
    return float(m.group(1)) if m else None

def main():
    text = urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 (Claude-Usage price updater)"}), timeout=30).read().decode()
    rows = {}
    for line in text.split("## Model pricing", 1)[1].split("\n## ", 1)[0].splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) != 6 or not c[0].startswith("Claude "): continue
        p, i, o, cr = prefix(c[0]), money(c[1]), money(c[5]), money(re.sub(r"<sup>.*?</sup>", "", c[4]))
        if None in (p, i, o, cr): sys.exit(f"cannot read row: {line[:80]}")
        rows.setdefault(p, []).append((i, o, cr, "over 100,000" in c[0]))
    models = []
    for p, r in rows.items():
        base = next((x for x in r if not x[3]), None)
        if not base: sys.exit(f"no base row for {p}")
        e = {"prefix": p, "input": base[0], "output": base[1], "cacheRead": base[2]}
        long = next((x for x in r if x[3]), None)
        if long: e["longMultiplier"] = round(long[0] / base[0], 3)
        models.append(e)
    old = json.loads(OUT.read_text())
    if len(models) < max(8, len(old["models"]) - 4): sys.exit(f"only {len(models)} models parsed – page layout changed?")
    for e in models:
        o = next((x for x in old["models"] if x["prefix"] == e["prefix"]), None)
        if o and not (0.1 <= e["input"] / o["input"] <= 10): sys.exit(f"{e['prefix']} price moved more than 10x – check by hand")
    if models == old["models"]: print("prices unchanged"); return
    old["models"], old["updated"] = models, datetime.date.today().isoformat()
    OUT.write_text(json.dumps(old, indent=2) + "\n"); print("pricing.json updated:", len(models), "models")

main()
