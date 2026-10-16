#!/usr/bin/env python3
"""Draws the doc diagrams in docs/*.svg in one dark-card style. Run: python3 docs/make-diagrams.py"""
import pathlib
from html import escape

OUT = pathlib.Path(__file__).resolve().parent
W = 1000
HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-labelledby="t d">'
        '<title id="t">{title}</title><desc id="d">{desc}</desc><defs>'
        '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1c1c1f"/><stop offset="1" stop-color="#0d0d0f"/></linearGradient>'
        '<marker id="ar" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M1 1 L9 5 L1 9" fill="none" stroke="#ff8a5c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></marker>'
        '<style>text{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Helvetica,Arial,sans-serif}}'
        '.k{{font-size:12px;font-weight:600;letter-spacing:.09em;fill:#ff8a5c}}.h{{font-weight:700;fill:#f4f1ee}}.s{{fill:#b3ada7}}.f{{font-size:14px;fill:#b3ada7}}'
        '.c{{fill:#232326;stroke:#3a3a3f;stroke-width:1.2}}.a{{stroke:#ff8a5c}}'
        '@media (prefers-reduced-motion:no-preference){{.arrow{{stroke-dasharray:5 5;animation:flow 1.2s linear infinite}}}}@keyframes flow{{to{{stroke-dashoffset:-10}}}}'
        '</style></defs><rect width="{w}" height="{h}" rx="16" fill="url(#bg)" stroke="#2c2c30"/>')

def flow(name, title, desc, nodes, footer=None):
    """nodes: (kicker, title, 'line|line'); the last card is the outcome and gets the accent border."""
    n = len(nodes); gap = 30 if n > 4 else 40; pad = 28
    cw = (W - 2 * pad - gap * (n - 1)) / n
    big = n <= 4
    ts, ls, ly = (19, 14, 22) if big else (16, 13, 19)
    top, ch = 40, 150
    h = top + ch + (62 if footer else 40)
    o = [HEAD.format(w=W, h=h, title=escape(title), desc=escape(desc))]
    for i, (k, t, lines) in enumerate(nodes):
        x = pad + i * (cw + gap); tx = x + 18
        o.append(f'<rect class="c{" a" if i == n - 1 else ""}" x="{x:.1f}" y="{top}" width="{cw:.1f}" height="{ch}" rx="12"/>')
        o.append(f'<text class="k" x="{tx:.1f}" y="{top+32}">{escape(k)}</text><text class="h" style="font-size:{ts}px" x="{tx:.1f}" y="{top+62}">{escape(t)}</text>')
        for j, ln in enumerate(lines.split("|")):
            o.append(f'<text class="s" style="font-size:{ls}px" x="{tx:.1f}" y="{top+90+j*ly}">{escape(ln)}</text>')
        if i < n - 1:
            ax = x + cw + 4
            o.append(f'<path class="arrow" d="M{ax:.1f} {top+ch/2} H{ax+gap-10:.1f}" stroke="#ff8a5c" stroke-width="2" fill="none" marker-end="url(#ar)" stroke-linecap="round"/>')
    if footer:
        o.append(f'<text class="f" x="{W/2}" y="{top+ch+38}" text-anchor="middle">{escape(footer)}</text>')
    o.append('</svg>')
    (OUT / name).write_text("\n".join(o) + "\n")

flow("windows-sync.svg", "How Windows logs reach Claude Usage on a Mac",
     "Claude Code logs on the Windows PC are copied by Sync-ClaudeLogs.ps1 into a synced folder, which the Mac app reads under Settings, Data, Other computers.",
     [("WINDOWS PC", "Claude Code", "Logs in|.claude\\projects"), ("HELPER", "Sync-ClaudeLogs", "Copies new .jsonl files|every 5 minutes"),
      ("SYNCED FOLDER", "Your sync service", "iCloud, OneDrive,|Dropbox or Syncthing"), ("YOUR MAC", "Claude Usage", "Settings → Data →|Other computers")])

flow("update-trust.svg", "How an update is checked before it installs",
     "An update must come from this repo's GitHub releases over HTTPS, carry a valid Ed25519 signature for that exact version, match its SHA-256, and have the right bundle id, version and code signature. Any failure discards it.",
     [("1 · SOURCE", "GitHub", "This repo's releases|over HTTPS only"), ("2 · SIGNATURE", "Ed25519", "Valid for this|exact version"),
      ("3 · CHECKSUM", "SHA-256", "Must match the|published value"), ("4 · THE APP", "Bundle check", "Id, version and|code signature"),
      ("5 · RESULT", "Install", "Any failed check|discards it")],
     "The signing key is kept offline, never on GitHub. The app never builds or runs code from the repository.")

flow("release-flow.svg", "The release order",
     "Bump the version, build and self-test, push, wait for green CI, do a dry run, then release.",
     [("1", "bump.sh", "Version and|change log"), ("2", "build.sh", "Build and|--selftest"), ("3", "Push", "Commit, pull|--rebase, push"),
      ("4", "CI", "Green for that|exact commit"), ("5", "Dry run", "release.sh|--dry-run"), ("6", "Release", "Signed DMG|+ Homebrew")],
     "release.sh refuses to run if any check is missing. One order, every time.")

flow("contribute-flow.svg", "From a change to a pull request",
     "Build, run the self-test, run bump.sh, then open a pull request that CI checks on macOS 14, 15 and latest.",
     [("1", "Build", "./build.sh"), ("2", "Self-test", "--selftest"), ("3", "Bump", "./bump.sh patch|\"short note\""), ("4", "Pull request", "CI runs on macOS|14, 15 and latest")])

# --- privacy: one hub, up to three destinations
def privacy():
    h = 330
    o = [HEAD.format(w=W, h=h, title="What Claude Usage talks to", desc="Your data stays on your Mac. The app asks Anthropic for your usage limits, ChatGPT only if you connect it, and GitHub for updates, the change log and model prices. There are no analytics.")]
    o.append('<rect class="c a" x="28" y="40" width="330" height="214" rx="12"/>')
    o.append('<text class="k" x="48" y="72">YOUR MAC</text><text class="h" style="font-size:22px" x="48" y="102">Claude Usage</text>')
    for j, ln in enumerate(["History, settings and profile", "photo stay here.", "Claude Code logs and sign-in", "are read-only, never stored."]):
        o.append(f'<text class="s" style="font-size:14px" x="48" y="{132+j*24}">{escape(ln)}</text>')
    dest = [("ANTHROPIC", "Your usage limits", "api.anthropic.com"), ("CHATGPT · ONLY IF YOU CONNECT IT", "Your ChatGPT limits", "chatgpt.com"), ("GITHUB", "Updates, change log and model prices", "github.com")]
    for i, (k, t, host) in enumerate(dest):
        y = 40 + i * 78
        o.append(f'<rect class="c" x="470" y="{y}" width="502" height="64" rx="12"/>')
        o.append(f'<text class="k" x="490" y="{y+24}">{escape(k)}</text><text class="h" style="font-size:17px" x="490" y="{y+47}">{escape(t)}</text>')
        o.append(f'<text class="s" style="font-size:13px" x="952" y="{y+47}" text-anchor="end">{escape(host)}</text>')
        o.append(f'<path class="arrow" d="M362 147 C 410 147, 410 {y+32}, 462 {y+32}" stroke="#ff8a5c" stroke-width="2" fill="none" marker-end="url(#ar)" stroke-linecap="round"/>')
    o.append(f'<text class="f" x="{W/2}" y="296" text-anchor="middle">No analytics, and nothing else is sent. Diagnostics are never sent automatically.</text></svg>')
    (OUT / "privacy-flow.svg").write_text("\n".join(o) + "\n")
privacy()
print("ok")
