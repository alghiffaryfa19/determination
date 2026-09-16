#!/bin/sh
# Session status for a continuing agent: branch state, stray work, open
# threads, device reachability. Read docs/CONTINUE.md before acting.
set -u
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

echo "== branch =="
git rev-parse --abbrev-ref HEAD
if git rev-parse --verify -q origin/main >/dev/null; then
    git rev-list --left-right --count origin/main...HEAD | awk '{print "  behind origin/main: "$1"  ahead: "$2}'
fi

echo "== uncommitted =="
git status --short | head -40
echo "  (other authors' in-flight work is expected; stage only your files)"

echo "== recent commits =="
git log --oneline -8 | sed 's/^/  /'

echo "== private branches =="
git branch --list 'private/*' | sed 's/^/  /'
grep -v '^#' .git/info/exclude 2>/dev/null | grep . | sed 's/^/  excluded: /'

echo "== newest handoff =="
handoff=$(ls -t docs/handoffs/*.md 2>/dev/null | head -1)
echo "  ${handoff:-none}"
if [ -n "${handoff:-}" ]; then
    echo "== open threads =="
    sed -n '/^## Open threads/,/^## /p' "$handoff" | sed '$d' | sed 's/^/  /'
fi

echo "== device =="
if command -v adb >/dev/null 2>&1; then
    adb devices | tail -n +2 | sed 's/^/  /'
else
    echo "  adb not on PATH"
fi

echo "== checks =="
echo "  behaviour: tools/check-host.sh   hygiene: tools/check-repo.sh"
echo "  links: python3 docs/check-links.py"
