#!/bin/sh
set -eu
REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export AURORA_SESSION_SELECT_ROOT=$ROOT
mkdir -p "$ROOT/etc/sessions" "$ROOT/guest/usr/bin"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/guest/usr/bin/test"
chmod 755 "$ROOT/guest/usr/bin/test"

cat > "$ROOT/etc/sessions/test.session" <<'EOF'
id=test
qualification=experimental
backend=test
compositor=/usr/bin/test
shell=/usr/bin/test
required_binaries=/usr/bin/test
EOF

printf '%s\n' test > "$ROOT/etc/compositor"
sh "$REPO/toggle/session-select" > "$ROOT/selected"
grep -q '^id=test$' "$ROOT/selected"

sed 's|shell=/usr/bin/test|shell=hyprland-config|' "$ROOT/etc/sessions/test.session" \
    > "$ROOT/etc/sessions/config-shell.session"
sed -i 's/^id=test$/id=config-shell/' "$ROOT/etc/sessions/config-shell.session"
printf '%s\n' config-shell > "$ROOT/etc/compositor"
sh "$REPO/toggle/session-select" > "$ROOT/config-shell"
grep -q '^id=config-shell$' "$ROOT/config-shell"
grep -q '^shell=hyprland-config$' "$ROOT/config-shell"

cat > "$ROOT/etc/sessions/test.session" <<'EOF'
id=test
qualification=experimental
backend=test
compositor=/usr/bin/test
required_binaries=/usr/bin/missing
EOF
printf '%s\n' test > "$ROOT/etc/compositor"
sh "$REPO/toggle/session-select" > "$ROOT/fallback" 2> "$ROOT/warn"
grep -q '^id=phosh$' "$ROOT/fallback"
grep -q 'requires missing guest executable' "$ROOT/warn"

echo 'session-select tests passed'
