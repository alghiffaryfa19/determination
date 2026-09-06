#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export DET_SESSION_SELECT_ROOT=$ROOT
mkdir -p "$ROOT/etc/sessions"
for qualification in qualified proven experimental diagnostic planned incompatible; do
    printf 'id=%s\nqualification=%s\ncompositor=/usr/bin/test\nreason=not ported\n' \
        "$qualification" "$qualification" > "$ROOT/etc/sessions/$qualification.session"
done
for id in qualified proven experimental diagnostic; do
    sh "$REPO/toggle/session-set" "$id"
    [ "$(cat "$ROOT/etc/compositor")" = "$id" ]
done
for id in planned incompatible missing '../qualified' "qualified';false" ''; do
    if sh "$REPO/toggle/session-set" "$id" 2>/dev/null; then
        echo "unexpectedly accepted: $id" >&2; exit 1
    fi
    [ "$(cat "$ROOT/etc/compositor")" = diagnostic ]
done
printf 'id=mismatch\nqualification=qualified\ncompositor=/usr/bin/test\n' > "$ROOT/etc/sessions/bad.session"
if sh "$REPO/toggle/session-set" bad 2>/dev/null; then exit 1; fi
[ "$(cat "$ROOT/etc/compositor")" = diagnostic ]
[ -z "$(find "$ROOT/etc" -name '.compositor.*')" ]
echo 'session-set tests passed'
