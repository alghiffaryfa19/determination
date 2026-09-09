#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
PROC=$ROOT/proc
mkdir -p "$PROC/100" "$PROC/101" "$PROC/102" "$ROOT/run"

printf '100 (provider) S 1 0 0 0\n' > "$PROC/100/stat"
printf '101 (other) S 1 0 0 0\n' > "$PROC/101/stat"
printf '102 (app) S 1 0 0 0\n' > "$PROC/102/stat"
printf '/system/bin/app_process\000/system/bin\000com.android.commands.content.Content\000call\000--uri\000content://g.tqyipmcoon.provider\000--user\0000\000--method\000log\000' > "$PROC/100/cmdline"
printf '/system/bin/app_process\000/system/bin\000com.android.commands.content.Content\000call\000--uri\000content://g.tqyipmcoon.provider.evil\000--user\0000\000--method\000log\000' > "$PROC/101/cmdline"
printf '/system/bin/app_process\000/system/bin\000com.android.commands.am.Am\000broadcast\000' > "$PROC/102/cmdline"

DET="$ROOT" DET_PROC_ROOT="$PROC" DET_MEMORY_PIDS='100 101 102' \
    sh "$REPO/toggle/desktop-memory" status > "$ROOT/status"
grep -qx 'matching_workers=1' "$ROOT/status"
grep -qx 'pid=100' "$ROOT/status"

DET="$ROOT" DET_PROC_ROOT="$PROC" DET_MEMORY_PIDS='100 101 102' DET_MEMORY_DRY_RUN=1 \
    sh "$REPO/toggle/desktop-memory" reclaim 7 > "$ROOT/reclaim"
grep -qx 'generation=7' "$ROOT/run/desktop-memory.state"
grep -qx 'matching_before=1' "$ROOT/run/desktop-memory.state"
grep -qx 'term_sent=0' "$ROOT/run/desktop-memory.state"
grep -qx 'matching_after=1' "$ROOT/run/desktop-memory.state"

DET="$ROOT" DET_PROC_ROOT="$PROC" DET_MEMORY_PIDS='100 101 102' \
    sh "$REPO/toggle/desktop-memory" release 7 > "$ROOT/release"
grep -qx 'mode=release' "$ROOT/run/desktop-memory.state"
if DET="$ROOT" DET_PROC_ROOT="$PROC" DET_MEMORY_PIDS='100 101 102' \
    sh "$REPO/toggle/desktop-memory" reclaim nope 2>/dev/null; then
    echo 'accepted invalid generation' >&2
    exit 1
fi
echo 'desktop-memory tests passed'
