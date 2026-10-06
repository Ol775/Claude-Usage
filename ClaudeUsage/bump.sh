#!/bin/zsh
# Usage: ./bump.sh minor|patch "what changed"   – updates VERSION and adds a CHANGELOG entry.
set -e
cd "$(dirname "$0")"
kind="${1:-}"; note="${2:-}"
[ -z "$kind" ] || [ -z "$note" ] && { echo "usage: ./bump.sh minor|patch \"what changed\""; exit 1; }
IFS=. read -r maj min pat < VERSION
case "$kind" in
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  *) echo "kind must be major, minor or patch"; exit 1 ;;
esac
new="$maj.$min.$pat"
echo "$new" > VERSION
python3 - "$new" "$note" <<'PY'
import sys
v, note = sys.argv[1], sys.argv[2]
s = open("CHANGELOG.md").read()
marker = "## "
i = s.index(marker)
open("CHANGELOG.md", "w").write(s[:i] + f"## {v} – alpha\n- {note}\n\n" + s[i:])
PY
# keep the README heading in step with the version
python3 - "$new" <<'PY'
import re, sys
p = "../README.md"
s = open(p).read()
s = re.sub(r"## ClaudeUsage  \(v[^)]*\)", f"## ClaudeUsage  (v{sys.argv[1]} alpha)", s, count=1)
open(p, "w").write(s)
PY
echo "Version is now $new"
