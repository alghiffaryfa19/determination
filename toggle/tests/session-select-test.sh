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

# A manifest may offer alternatives per distro path; the launcher must receive
# the one that exists here, not the first one written.
mkdir -p "$ROOT/guest/usr/local/bin"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/guest/usr/local/bin/only-here"
chmod 755 "$ROOT/guest/usr/local/bin/only-here"
cat > "$ROOT/etc/sessions/alts.session" <<'EOF'
id=alts
qualification=experimental
backend=test
compositor=/usr/libexec/missing-compositor|/usr/local/bin/only-here
shell=/usr/libexec/missing-shell|/usr/local/bin/only-here
required_binaries=/usr/libexec/missing-shell|/usr/local/bin/only-here
EOF
printf '%s\n' alts > "$ROOT/etc/compositor"
sh "$REPO/toggle/session-select" > "$ROOT/alts" 2> "$ROOT/alts-warn"
grep -qx '^id=alts$' "$ROOT/alts"
grep -qx '^compositor=/usr/local/bin/only-here$' "$ROOT/alts"
grep -qx '^shell=/usr/local/bin/only-here$' "$ROOT/alts"

# ...and refuses when no alternative exists.
cat > "$ROOT/etc/sessions/alts.session" <<'EOF'
id=alts
qualification=experimental
backend=test
compositor=/usr/libexec/absent|/usr/local/bin/absent
EOF
printf '%s\n' alts > "$ROOT/etc/compositor"
sh "$REPO/toggle/session-select" > "$ROOT/alts-fallback" 2>/dev/null
grep -qx '^id=phosh$' "$ROOT/alts-fallback"
echo "session manifest alternative tests passed"
