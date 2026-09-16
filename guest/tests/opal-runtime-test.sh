#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/prefix/bin" "$WORK/prefix/lib/qt6/plugins/platforms" "$WORK/config"
sed "s|^CONFIG=.*|CONFIG=$WORK/config|" "$ROOT/guest/aurora-opal" > "$WORK/opal"
touch "$WORK/config/shell.qml"
test -r "$ROOT/guest/opal/osk_theme.py"
for plugin in egl generic; do
    touch "$WORK/prefix/lib/qt6/plugins/platforms/libqwayland-$plugin.so"
done
cat > "$WORK/prefix/bin/quickshell" <<'SH'
#!/bin/sh
[ "$*" = --version ] || exit 99
exit "${VERSION_RC:-0}"
SH
cat > "$WORK/bin/ldd" <<'SH'
#!/bin/sh
case "$LD_LIBRARY_PATH" in
    "$AURORA_DHYPRLAND_PREFIX/lib/compat:$AURORA_DHYPRLAND_PREFIX/lib:"*) ;;
    *) exit 98 ;;
esac
case "$1" in
    *libqwayland-egl.so)
        [ "${MISSING_DEP:-0}" = 0 ] || echo 'libQt6WaylandClient.so.6 => not found'
        ;;
esac
exit 0
SH
chmod +x "$WORK/prefix/bin/quickshell" "$WORK/bin/ldd"
export PATH="$WORK/bin:$PATH" AURORA_DHYPRLAND_PREFIX="$WORK/prefix"
sh "$WORK/opal" check > "$WORK/log"
grep -Fq 'runtime dependencies ready (display not tested)' "$WORK/log"
if MISSING_DEP=1 sh "$WORK/opal" check > "$WORK/log" 2>&1; then
    echo 'Preflight accepted an unresolved Wayland dependency' >&2; exit 1
fi
grep -Fq 'unresolved dependencies' "$WORK/log"
if VERSION_RC=1 sh "$WORK/opal" check > "$WORK/log" 2>&1; then
    echo 'Preflight accepted a broken executable' >&2; exit 1
fi
rm "$WORK/prefix/lib/qt6/plugins/platforms/libqwayland-generic.so"
if sh "$WORK/opal" check > "$WORK/log" 2>&1; then
    echo 'Preflight accepted a missing Wayland plugin' >&2; exit 1
fi
grep -Fq 'missing' "$WORK/log"
echo 'Opal runtime preflight tests passed'
