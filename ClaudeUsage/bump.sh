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
stage=$(grep '^STAGE=' build.sh | cut -d'"' -f2)      # alpha / beta / stable – set once in build.sh
echo "$new" > VERSION
python3 - "$new" "$note" "$stage" <<'PY'
import sys
from datetime import date
v, note, stage = sys.argv[1], sys.argv[2], sys.argv[3]
s = open("CHANGELOG.md").read()
marker = "## "
i = s.index(marker)
open("CHANGELOG.md", "w").write(s[:i] + f"## {v} – {stage} ({date.today().isoformat()})\n- {note}\n\n" + s[i:])
PY
# keep the README heading in step with the version
python3 - "$new" "$stage" <<'PY'
import re, sys
p = "../README.md"
s = open(p).read()
s = re.sub(r"<!--v-->.*?<!--/v-->", f"<!--v-->v{sys.argv[1]} {sys.argv[2]}<!--/v-->", s, count=1)
open(p, "w").write(s)
PY
echo $(( $(git rev-list --count HEAD 2>/dev/null || echo 0) + 1 )) > BUILD_NUMBER    # the build number this change will have once committed
echo "Version is now $new"
