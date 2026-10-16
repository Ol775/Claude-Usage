#!/usr/bin/env python3
"""Draws docs/roadmap.svg from ROADMAP.md (✅ = done) and ClaudeUsage/VERSION. Run by .github/workflows/roadmap.yml."""
import os, re, pathlib, subprocess
from html import escape

root = pathlib.Path(__file__).resolve().parents[2]
text = (root / "ROADMAP.md").read_text()
def latest_release():
    """Latest published release (LATEST_TAG from the workflow, else gh, else the VERSION file)."""
    tag = os.environ.get("LATEST_TAG", "")
    if not tag:
        try:
            tag = subprocess.run(["gh", "release", "view", "--json", "tagName", "-q", ".tagName"], capture_output=True, text=True, cwd=root, timeout=20).stdout.strip()
        except Exception:
            tag = ""
    return (tag or (root / "ClaudeUsage/VERSION").read_text()).strip().lstrip("v")
version = latest_release()
stage = re.search(r'^STAGE="([^"]+)"', (root / "ClaudeUsage/build.sh").read_text(), re.M).group(1)

def section(heading_re):
    m = re.search(heading_re + r'.*?(?=\n##? |\Z)', text, re.S | re.M)
    return m.group(0) if m else ""

def count(block):
    """Top-level bullets only: done if the bullet carries a ✅."""
    items = [l for l in block.split("\n") if re.match(r"- ", l)]
    return sum("✅" in l[:8] for l in items), len(items)

phases = []
for m in re.finditer(r'^### (B\d)\. ([^\n]+?)(?: [✅⏳🚧].*)?$', text, re.M):
    block = text[m.end(): (re.search(r'\n##', text[m.end():]) or re.search(r'\Z', text[m.end():])).start() + m.end()]
    done, total = count(block)
    phases.append((m.group(1), m.group(2).strip(), done, total))
gates_block = section(r'^## 1\.0 production gates')
g_items = [l for l in gates_block.split("\n") if re.match(r"- [✅⏳]", l)]
g_done, g_total = sum(l.startswith("- ✅") for l in g_items), len(g_items)
rows = phases + [("1.0", "Production gates", g_done, g_total)]
d_all, t_all = sum(r[2] for r in rows), sum(r[3] for r in rows)
pct = round(100 * d_all / t_all) if t_all else 0

W, X0, XB, BW = 1000, 36, 372, 490
H = 196 + 44 * len(rows) + 24
o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-labelledby="t d">',
     f'<title id="t">Claude Usage roadmap: {pct}% of the beta to 1.0 work is done</title>',
     '<desc id="d">' + escape("; ".join(f"{r[1]} {r[2]} of {r[3]}" for r in rows)) + '</desc>',
     '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1c1c1f"/><stop offset="1" stop-color="#0d0d0f"/></linearGradient>'
     '<linearGradient id="ac" x1="0" x2="1"><stop offset="0" stop-color="#ff8a5c"/><stop offset="1" stop-color="#ffb37f"/></linearGradient>'
     '<style>text{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Helvetica,Arial,sans-serif}'
     '.k{font-size:12px;font-weight:600;letter-spacing:.09em;fill:#ff8a5c}.h{font-size:26px;font-weight:700;fill:#f4f1ee}'
     '.l{font-size:16px;font-weight:600;fill:#f4f1ee}.s{font-size:14px;fill:#b3ada7}.n{font-size:14px;font-weight:600;fill:#f4f1ee}'
     '.tr{fill:#2b2b2f}.bar{transform-box:fill-box;transform-origin:left center;animation:grow 1.1s cubic-bezier(.2,.7,.2,1) both}'
     '.ping{animation:ping 2s ease-out infinite;transform-box:fill-box;transform-origin:center}'
     '@keyframes grow{from{transform:scaleX(0)}}@keyframes ping{from{opacity:.7;transform:scale(1)}to{opacity:0;transform:scale(2.6)}}'
     '@media (prefers-reduced-motion:reduce){.bar,.ping{animation:none}.ping{opacity:0}}</style></defs>',
     f'<rect width="{W}" height="{H}" rx="16" fill="url(#bg)" stroke="#2c2c30"/>',
     f'<text class="k" x="{X0}" y="44">ROADMAP TO 1.0</text>',
     f'<text class="h" x="{X0}" y="76">{pct}% of the beta work is done</text>',
     f'<text class="s" x="{W-X0}" y="76" text-anchor="end">latest release v{escape(version)} · {escape(stage)} · {d_all} of {t_all} items</text>']
# timeline: alpha -> beta (here) -> 1.0
ty, xs = 128, [X0 + 20, (W // 2), W - X0 - 20]
o.append(f'<line x1="{xs[0]}" y1="{ty}" x2="{xs[2]}" y2="{ty}" stroke="#3a3a3f" stroke-width="3" stroke-linecap="round"/>')
o.append(f'<line x1="{xs[0]}" y1="{ty}" x2="{xs[1]}" y2="{ty}" stroke="#ff8a5c" stroke-width="3" stroke-linecap="round"/>')
o.append(f'<line class="bar" x1="{xs[1]}" y1="{ty}" x2="{xs[1] + (xs[2]-xs[1]) * d_all // max(t_all,1)}" y2="{ty}" stroke="#ff8a5c" stroke-width="3" stroke-linecap="round"/>')
labels = [("Alpha", "complete", True), (f"Beta · you are here", f"v{version}", None), ("1.0", f"{g_done} of {g_total} gates", False)]
for x, (a, b, state) in zip(xs, labels):
    anchor = "start" if x == xs[0] else ("end" if x == xs[2] else "middle")
    tx = x - 20 if anchor == "start" else (x + 20 if anchor == "end" else x)
    fill = "#ff8a5c" if state is not False else "#232326"
    o.append(f'<circle cx="{x}" cy="{ty}" r="9" fill="{fill}" stroke="#ff8a5c" stroke-width="2"/>')
    if state is None:
        o.append(f'<circle class="ping" cx="{x}" cy="{ty}" r="9" fill="none" stroke="#ff8a5c" stroke-width="2"/>')
    o.append(f'<text class="n" x="{tx}" y="{ty+34}" text-anchor="{anchor}">{escape(a)}</text><text class="s" x="{tx}" y="{ty+54}" text-anchor="{anchor}">{escape(b)}</text>')
# phase rows
y = 206
for i, (key, name, done, total) in enumerate(rows):
    full = total and done == total
    frac = done / total if total else 0
    o.append(f'<text class="k" x="{X0}" y="{y+5}">{escape(key)}</text><text class="l" x="{X0+44}" y="{y+5}">{escape(name)}</text>')
    o.append(f'<rect class="tr" x="{XB}" y="{y-9}" width="{BW}" height="14" rx="7"/>')
    if done:
        o.append(f'<rect class="bar" style="animation-delay:{i*0.12:.2f}s" x="{XB}" y="{y-9}" width="{BW*frac:.1f}" height="14" rx="7" fill="{"#5fbf8a" if full else "url(#ac)"}"/>')
    o.append(f'<text class="n" x="{XB+BW+22}" y="{y+5}">{done} / {total}{"  ✓" if full else ""}</text>')
    y += 44
o.append('</svg>')
(root / "docs/roadmap.svg").write_text("\n".join(o) + "\n")
print(f"{pct}% ({d_all}/{t_all})", [(r[0], r[2], r[3]) for r in rows])
