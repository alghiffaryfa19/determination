#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export TEST_LOG="$WORK/calls"

cat > "$WORK/bin/busctl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$TEST_LOG"
case "$*" in
    '--user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible')
        printf '%s\n' 'b false'
        ;;
    '--user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true'|\
    '--user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false')
        printf '%s\n' '()'
        ;;
    *)
        echo "unexpected busctl call: $*" >&2
        exit 1
        ;;
esac
EOF
chmod 0755 "$WORK/bin/busctl"

PATH="$WORK/bin" "$ROOT/guest/aurora-osk" show >/dev/null
tail -1 "$TEST_LOG" | grep -Fxq -- \
    '--user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true'

: > "$TEST_LOG"
PATH="$WORK/bin" "$ROOT/guest/aurora-osk" hide >/dev/null
tail -1 "$TEST_LOG" | grep -Fxq -- \
    '--user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false'

: > "$TEST_LOG"
PATH="$WORK/bin" "$ROOT/guest/aurora-osk" toggle >/dev/null
sed -n '1p' "$TEST_LOG" | grep -Fxq -- \
    '--user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible'
sed -n '2p' "$TEST_LOG" | grep -Fxq -- \
    '--user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true'

cat > "$WORK/preferences.json" <<'EOF'
{"light":false,"dynamicColors":true,"dynamicPalette":{"dark":{"primary":"#123456","on_primary":"#ffffff","primary_container":"#334455","on_primary_container":"#ddeeff","background":"#101112","on_surface":"#f1f2f3","on_surface_variant":"#c1c2c3","surface_container":"#202122","surface_container_high":"#303132","outline_variant":"#505152"}}}
EOF
XDG_RUNTIME_DIR="$WORK/runtime" XDG_CONFIG_HOME="$WORK/config" python3 - "$ROOT/guest/opal/osk_theme.py" "$WORK/preferences.json" <<'PY'
import importlib.util
import pathlib
import sys

spec=importlib.util.spec_from_file_location('aurora_osk_theme',sys.argv[1])
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
css=module.css_for(module.read_preferences(sys.argv[2]))
assert 'background: #123456;' in css
assert 'background-color: #202122;' in css
assert 'border-radius: 15px;' in css
assert 'Google Sans Flex' in css
runtime=module.prepare_runtime(sys.argv[2])
assert (runtime/'gtk-3.0'/'gtk.css').is_file()
PY

if grep -Eq '^exec-once *=.*squeekboard' "$ROOT/guest/hyprland-opal.conf"; then
    echo 'Opal session still starts a duplicate unthemed Squeekboard instance' >&2
    exit 1
fi
grep -Fq 'class SystemOsk:' "$ROOT/guest/opal/backend.py"
grep -Fq "with_name('osk_theme.py')" "$ROOT/guest/opal/backend.py"

echo 'aurora-osk tests passed'
