#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export DET_SESSION_SELECT_ROOT=$ROOT
mkdir -p "$ROOT/etc/sessions" "$ROOT/guest/usr/bin"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/guest/usr/bin/test"
chmod +x "$ROOT/guest/usr/bin/test"
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
printf 'id=missing-binary\nqualification=experimental\ncompositor=/usr/bin/test\nrequired_binaries=/usr/bin/not-installed\n' > "$ROOT/etc/sessions/missing-binary.session"
if sh "$REPO/toggle/session-set" missing-binary 2>/dev/null; then exit 1; fi
[ "$(cat "$ROOT/etc/compositor")" = diagnostic ]
printf 'id=config-shell\nqualification=experimental\ncompositor=/usr/bin/test\nshell=hyprland-config\n' > "$ROOT/etc/sessions/config-shell.session"
sh "$REPO/toggle/session-set" config-shell
[ "$(cat "$ROOT/etc/compositor")" = config-shell ]
sh "$REPO/toggle/session-catalog" > "$ROOT/catalog"
grep -q '^runtime_ready=yes$' "$ROOT/catalog"
grep -q '^runtime_reason=Missing guest executable: /usr/bin/not-installed$' "$ROOT/catalog"
[ -z "$(find "$ROOT/etc" -name '.compositor.*')" ]
echo 'session-set tests passed'
