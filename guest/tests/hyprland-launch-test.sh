#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/prefix/bin" "$WORK/prefix/lib/compat" "$WORK/prefix/lib"

cat > "$WORK/prefix/bin/Hyprland" <<'EOF'
#!/bin/sh
set -eu
{
    printf 'LD_LIBRARY_PATH=%s\n' "$LD_LIBRARY_PATH"
    printf 'EGL_PLATFORM=%s\n' "$EGL_PLATFORM"
    printf 'HYBRIS_EGLPLATFORM=%s\n' "$HYBRIS_EGLPLATFORM"
    printf 'AURORA_HYBRIS_HWC=%s\n' "$AURORA_HYBRIS_HWC"
    printf 'LIBSEAT_BACKEND=%s\n' "$LIBSEAT_BACKEND"
    printf 'ARGS=%s\n' "$*"
} > "$AURORA_TEST_LOG"
EOF
chmod 0755 "$WORK/prefix/bin/Hyprland"

AURORA_TEST_LOG="$WORK/log" \
AURORA_DHYPRLAND_PREFIX="$WORK/prefix" \
AURORA_HYPRLAND_CONFIG="$WORK/hyprland.conf" \
DBUS_SESSION_BUS_ADDRESS="unix:path=$WORK/bus" \
XDG_RUNTIME_DIR="$WORK/runtime" \
    "$ROOT/guest/aurora-hyprland" --verify-test-arg

grep -Fq "LD_LIBRARY_PATH=$WORK/prefix/lib/compat:$WORK/prefix/lib:" "$WORK/log"
grep -Fxq 'EGL_PLATFORM=null' "$WORK/log"
grep -Fxq 'HYBRIS_EGLPLATFORM=null' "$WORK/log"
grep -Fxq 'AURORA_HYBRIS_HWC=1' "$WORK/log"
grep -Fxq 'LIBSEAT_BACKEND=seatd' "$WORK/log"
grep -Fxq "ARGS=--config $WORK/hyprland.conf --verify-test-arg" "$WORK/log"

echo 'Hyprland launcher behavior tests passed'
